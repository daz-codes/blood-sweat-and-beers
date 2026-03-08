# WorkoutValidator performs deterministic, rule-based checks on a generated
# workout data hash (the raw LLM output before it's persisted) and auto-fixes
# any violations it can resolve without another API call.
#
# Usage:
#   validator    = WorkoutValidator.new(workout_data, difficulty: "intermediate", duration_mins: 45)
#   workout_data = validator.validate_and_fix
#   validator.fixes.each    { |msg| Rails.logger.info("[WorkoutValidator] Fixed: #{msg}") }
#   validator.warnings.each { |msg| Rails.logger.warn("[WorkoutValidator] Warn:  #{msg}") }
#
# validate_and_fix mutates the hash in place AND returns it.
class WorkoutValidator
  # Max total reps across all exercises within a single EMOM minute, per difficulty.
  EMOM_REP_CAPS = {
    "beginner"     => 6,
    "intermediate" => 9,
    "advanced"     => 12
  }.freeze

  # Valid step-size range per ladder/mountain metric.
  # distance_m has no upper bound — just a minimum of 10.
  LADDER_STEP_MIN = { "reps" => 1, "calories" => 5, "distance_m" => 10, "kg" => 5 }.freeze
  LADDER_STEP_MAX = { "reps" => 5, "calories" => 10, "kg" => 10 }.freeze  # distance_m: no max

  # Exercises that work one side at a time — rep counts must be even so both sides get equal work.
  ALTERNATING_PATTERN = /lunge|split.?squat|step.?up|single.?arm|single.?leg|one.?arm|one.?leg|pistol|alternating|unilateral/i.freeze

  attr_reader :fixes, :warnings

  def initialize(workout_data, difficulty:, duration_mins:)
    @data          = workout_data
    @difficulty    = difficulty
    @duration_mins = duration_mins.to_i
    @fixes         = []
    @warnings      = []
  end

  def validate_and_fix
    sections = Array(@data.dig("structure", "sections"))

    sections.each_with_index do |section, idx|
      case section["format"]
      when "emom"
        fix_emom_structure(section, idx)
        fix_emom_reps(section, idx)
      when "tabata"
        fix_tabata_duration(section, idx)
        fix_tabata_exercise_count(section, idx)
      when "ladder", "mountain"
        fix_ladder_step(section, idx)
      when "hundred"
        fix_hundred(section, idx)
      end
    end

    fix_alternating_reps(sections)
    fix_rest_secs(sections)
    fix_single_set_sections(sections)
    fix_tabata_exercise_notes(sections)
    check_cooldown(sections)

    @data
  end

  private

  # EMOM circuit: total reps per minute must not exceed the difficulty cap.
  # Rotating EMOMs don't have a per-minute rep cap (each exercise fills its own minute).
  # Scales all rep exercises proportionally, flooring each to at least 1.
  def fix_emom_reps(section, idx)
    return if section["emom_style"] == "rotating"
    cap = EMOM_REP_CAPS[@difficulty] || 12
    rep_exercises = Array(section["exercises"]).select { |e| e["reps"].to_i > 0 }
    total = rep_exercises.sum { |e| e["reps"].to_i }
    return if total <= cap || rep_exercises.empty?

    scale = cap.to_f / total
    rep_exercises.each do |ex|
      ex["reps"] = [(ex["reps"].to_i * scale).floor, 1].max
    end

    new_total = rep_exercises.sum { |e| e["reps"].to_i }
    @fixes << "EMOM '#{section["name"]}': scaled reps #{total} → #{new_total} " \
              "(#{@difficulty} cap: #{cap}/min)"
  end

  # EMOM circuit: max 3 exercises per minute.
  # EMOM rotating: duration_mins must be a multiple of exercise count.
  def fix_emom_structure(section, idx)
    exercises = Array(section["exercises"])
    style = section["emom_style"]

    if style == "rotating"
      n = exercises.size
      return if n.zero?
      dur = section["duration_mins"].to_i
      return if dur.zero? || (dur % n).zero?
      snapped = ((dur.to_f / n).ceil * n)
      section["duration_mins"] = snapped
      @fixes << "EMOM rotating '#{section["name"]}': duration_mins #{dur} → #{snapped} (must be multiple of #{n} exercises)"
    else
      # circuit — cap at 3 exercises
      return if exercises.size <= 3
      section["exercises"] = exercises.first(3)
      @fixes << "EMOM circuit '#{section["name"]}': trimmed to 3 exercises (was #{exercises.size})"
    end
  end

  # Tabata exercises must be a factor of 8: 1, 2, 4, or 8.
  # Each exercise fills 8/n rounds. Truncates to nearest valid count (never pads).
  TABATA_VALID_COUNTS = [1, 2, 4, 8].freeze

  def fix_tabata_exercise_count(section, idx)
    exercises = Array(section["exercises"])
    n = exercises.size
    return if TABATA_VALID_COUNTS.include?(n)

    snapped = TABATA_VALID_COUNTS.select { |v| v <= n }.last || 1
    section["exercises"] = exercises.first(snapped)
    @fixes << "Tabata '#{section["name"]}': #{n} exercises → #{snapped} (must be 1, 2, 4, or 8)"
  end

  # Tabata is always exactly 4 minutes: 20s on + 10s off × 8 rounds = 240s.
  def fix_tabata_duration(section, idx)
    return if section["duration_mins"] == 4
    old = section["duration_mins"]
    section["duration_mins"] = 4
    @fixes << "Tabata '#{section["name"]}': corrected duration #{old} → 4 mins"
  end

  # Ladder/mountain: step size must be within the valid range for the varying metric.
  # Snaps up to the minimum if too small, down to the maximum if too large.
  def fix_ladder_step(section, idx)
    varies = section["varies"]
    step   = section["step"].to_f
    return unless varies && step > 0

    min = LADDER_STEP_MIN[varies]
    max = LADDER_STEP_MAX[varies]  # nil means no upper bound
    return unless min  # unknown metric — skip

    corrected = if step < min
      min
    elsif max && step > max
      max
    else
      return  # already valid
    end

    section["step"] = corrected
    @fixes << "#{section["format"].capitalize} '#{section["name"]}': " \
              "step #{step} invalid for #{varies} — corrected to #{corrected}"
  end

  # A section with straight/rounds format, exactly 1 exercise, and no rounds set
  # is almost certainly a mistake — enforce a minimum of 3 rounds.
  # Skips warm-up, cool-down, tabata, emom, amrap, for_time, ladder, mountain.
  SINGLE_SET_EXEMPT = %w[tabata emom amrap for_time ladder mountain matrix hundred].freeze
  WARMUP_COOLDOWN_PATTERN = /warm|cool|stretch|recovery/i

  def fix_single_set_sections(sections)
    sections.each do |section|
      next if section["format"].to_s.in?(SINGLE_SET_EXEMPT)
      next if section["name"].to_s.match?(WARMUP_COOLDOWN_PATTERN)
      next if section["rounds"].to_i > 1
      next if Array(section["exercises"]).size != 1
      section["rounds"]  = 3
      section["format"]  = "rounds"
      @fixes << "'#{section["name"]}': single exercise with no rounds — set to 3 rounds"
    end
  end

  # Snaps rest_secs to the nearest allowed value: 30, 45, or 60.
  # Any rest longer than 60s is capped at 60; anything below 30 stays as-is (short transitions are fine).
  ALLOWED_REST = [30, 45, 60].freeze

  def fix_rest_secs(sections)
    sections.each do |section|
      rest = section["rest_secs"].to_i
      next if rest.zero? || rest <= 20  # no rest or very short transition — leave alone
      snapped = ALLOWED_REST.min_by { |v| (v - rest).abs }
      next if snapped == rest
      @fixes << "'#{section["name"]}': rest_secs #{rest}s → #{snapped}s"
      section["rest_secs"] = snapped
    end
  end

  # Alternating/unilateral exercises must have even rep counts so both sides get equal work.
  # Rounds up odd counts by 1 rather than down, so volume is never reduced.
  # Skips ladder/mountain sections — those use progressive rep schemes where odd numbers are fine.
  def fix_alternating_reps(sections)
    sections.each do |section|
      next if section["format"].in?(%w[ladder mountain])
      Array(section["exercises"]).each do |exercise|
        next unless exercise["name"]&.match?(ALTERNATING_PATTERN)
        reps = exercise["reps"].to_i
        next if reps.zero? || reps.even?
        exercise["reps"] = reps + 1
        @fixes << "'#{exercise["name"]}' in '#{section["name"]}': reps #{reps} → #{reps + 1} (alternating — must be even)"
      end
    end
  end


  # Tabata exercises often get notes like "20s on / 10s off × 8 rounds" from the LLM.
  # This is already shown in the UI under each exercise name — strip it from notes to avoid duplication.
  def fix_tabata_exercise_notes(sections)
    sections.each do |section|
      next unless section["format"] == "tabata"
      Array(section["exercises"]).each do |exercise|
        next unless exercise["notes"].present?
        exercise.delete("notes")
        @fixes << "'#{exercise["name"]}' in '#{section["name"]}': removed tabata interval notes (shown in UI)"
      end
    end
  end

  # The Hundred: exactly 1 exercise with exactly 100 reps, done for time.
  # Trims to 1 exercise if multiple were given; corrects reps to 100.
  def fix_hundred(section, idx)
    exercises = Array(section["exercises"])
    if exercises.size > 1
      section["exercises"] = exercises.first(1)
      @fixes << "Hundred '#{section["name"]}': trimmed to 1 exercise (was #{exercises.size})"
    end
    if section["rounds"].to_i > 1
      section.delete("rounds")
      @fixes << "Hundred '#{section["name"]}': removed rounds (single all-out effort)"
    end
    ex = Array(section["exercises"]).first
    return unless ex
    unless ex["reps"].to_i == 100
      old = ex["reps"]
      ex["reps"] = 100
      @fixes << "Hundred '#{section["name"]}': reps #{old} → 100"
    end
  end

  # Warn if the last section doesn't look like a cool-down.
  def check_cooldown(sections)
    last = sections.last
    return if last.nil?
    return if last["name"]&.downcase&.match?(/cool|stretch|recovery/)
    @warnings << "No cool-down detected — last section is '#{last["name"]}'"
  end
end
