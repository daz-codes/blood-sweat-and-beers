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

  def initialize(workout_data, difficulty:, duration_mins:, main_tag_slug: nil)
    @data          = workout_data
    @difficulty    = difficulty
    @duration_mins = duration_mins.to_i
    @main_tag_slug = main_tag_slug.to_s
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

    if @main_tag_slug == "functional-muscle"
      fix_fm_remove_activation(sections)
      fix_fm_rotating_emom_reps(sections)
      fix_fm_tabata_remove_non_compounds(sections)
      fix_fm_merge_strength_sections(sections)
      fix_fm_strength_sets(sections)
      fix_fm_warmup(sections)
      fix_fm_strip_machine_suffix(sections)
    end

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
      ex["reps"] = [ (ex["reps"].to_i * scale).floor, 1 ].max
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
  TABATA_VALID_COUNTS = [ 1, 2, 4, 8 ].freeze

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

  # Any non-exempt section with fewer than 3 rounds and exactly 1 exercise is almost
  # certainly a mistake (single set). Enforce a minimum of 3 rounds.
  # Skips warm-up, cool-down, tabata, emom, amrap, for_time, ladder, mountain.
  SINGLE_SET_EXEMPT = %w[tabata emom amrap for_time ladder mountain matrix hundred].freeze
  WARMUP_COOLDOWN_PATTERN = /warm|cool|stretch|recovery/i

  def fix_single_set_sections(sections)
    sections.each do |section|
      next if section["format"].to_s.in?(SINGLE_SET_EXEMPT)
      next if section["name"].to_s.match?(WARMUP_COOLDOWN_PATTERN)
      next if section["rounds"].to_i >= 3
      next if Array(section["exercises"]).size != 1
      section["rounds"] = 3
      section["format"] = "rounds"
      @fixes << "'#{section["name"]}': single exercise with #{section["rounds"] || "no"} rounds — set to 3 rounds"
    end
  end

  # Snaps rest_secs to the nearest allowed value: 30, 45, or 60.
  # Any rest longer than 60s is capped at 60; anything below 30 stays as-is (short transitions are fine).
  ALLOWED_REST = [ 30, 45, 60 ].freeze

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

  # FM: strip any section whose name looks like an activation/mobility warm-up block.
  # These don't belong in Functional Muscle — warm-up is cardio machine only.
  FM_ACTIVATION_PATTERN = /activation|mobility|prep|dynamic warm|movement prep/i.freeze

  def fix_fm_remove_activation(sections)
    removed = sections.select { |s| s["name"].to_s.match?(FM_ACTIVATION_PATTERN) }
    removed.each do |s|
      sections.delete(s)
      @fixes << "FM: removed activation/mobility block '#{s["name"]}' — FM warm-up is cardio only"
    end
  end

  # FM: rotating EMOM exercises (12-min continuous block) fill the full minute —
  # they must NOT have reps, calories, or distance set. Strip them.
  def fix_fm_rotating_emom_reps(sections)
    sections.each do |section|
      next unless section["format"] == "emom" && section["emom_style"] == "rotating"
      Array(section["exercises"]).each do |ex|
        stripped = []
        %w[reps calories distance_m].each do |field|
          if ex[field].present?
            stripped << "#{field}: #{ex[field]}"
            ex.delete(field)
          end
        end
        next if stripped.empty?
        @fixes << "FM rotating EMOM '#{section["name"]}': removed #{stripped.join(", ")} from '#{ex["name"]}' — exercise fills the full minute"
      end
    end
  end

  # FM: strength sections (straight/rounds format, not warm-up/cool-down) must be
  # exactly 5 rounds with either 5 or 10 reps. Fix rounds to 5; snap reps to nearest.
  FM_STRENGTH_EXEMPT = %w[tabata emom amrap for_time ladder mountain matrix hundred].freeze
  FM_VALID_REPS      = [ 5, 10 ].freeze

  def fix_fm_strength_sets(sections)
    sections.each do |section|
      next if section["format"].to_s.in?(FM_STRENGTH_EXEMPT)
      next if section["name"].to_s.match?(WARMUP_COOLDOWN_PATTERN)

      # Fix rounds to 5
      if section["rounds"].to_i != 5
        old = section["rounds"]
        section["rounds"] = 5
        @fixes << "FM '#{section["name"]}': rounds #{old.inspect} → 5 (Functional Muscle requires 5 rounds)"
      end

      # Snap reps to 5 or 10
      Array(section["exercises"]).each do |ex|
        reps = ex["reps"].to_i
        next if reps.zero?
        next if FM_VALID_REPS.include?(reps)
        snapped = FM_VALID_REPS.min_by { |v| (v - reps).abs }
        ex["reps"] = snapped
        @fixes << "FM '#{ex["name"]}' in '#{section["name"]}': reps #{reps} → #{snapped} (FM only allows 5×5 or 5×10)"
      end
    end
  end

  # FM: warm-up must be a single cardio machine exercise (bike/row/ski), 5 mins, straight format.
  # If multiple exercises are found in the warm-up, trim to the first one.
  def fix_fm_warmup(sections)
    warmup = sections.find { |s| s["name"].to_s.match?(/warm/i) }
    return unless warmup

    exercises = Array(warmup["exercises"])
    if exercises.size > 1
      warmup["exercises"] = exercises.first(1)
      @fixes << "FM warm-up trimmed to 1 exercise (was #{exercises.size}) — FM warm-up is cardio machine only"
    end

    if warmup["duration_mins"].to_i != 5
      old = warmup["duration_mins"]
      warmup["duration_mins"] = 5
      @fixes << "FM warm-up duration #{old} → 5 mins"
    end
  end

  # FM: remove non-compound exercises from tabata sections.
  # A compound must contain a connector word joining two movements.
  # After removal the tabata exercise count fixer will snap to the next valid count.
  COMPOUND_CONNECTORS = /\band\b|\bwith\b|\bto\b|\binto\b|\b\+\b/i.freeze

  # FM: flag non-compound tabata exercises in the notes so they're visible,
  # but keep them rather than stripping (an empty tabata is worse).
  def fix_fm_tabata_remove_non_compounds(sections)
    sections.each do |section|
      next unless section["format"] == "tabata"
      Array(section["exercises"]).each do |ex|
        next if ex["name"].to_s.match?(COMPOUND_CONNECTORS)
        ex["notes"] = "⚠ Should be a compound movement (e.g. '#{ex["name"]} and Bicep Curl')"
        @warnings << "FM Tabata '#{section["name"]}': '#{ex["name"]}' is not a compound — flagged in notes"
      end
    end
  end

  # FM: collect ALL straight/rounds strength sections and consolidate into exactly
  # two: "Upper Body Strength" and "Lower Body Strength", each with rounds: 5.
  # Splits exercises by lower-body keyword; anything that doesn't match goes upper.
  LOWER_BODY_PATTERN = /squat|lunge|deadlift|romanian|leg press|leg extension|calf|glute|hip|hamstring|step.?up|box jump/i.freeze
  FM_STRENGTH_EXEMPT_FORMATS = %w[tabata emom amrap for_time ladder mountain matrix hundred].freeze
  FM_STRENGTH_EXEMPT_NAMES   = /warm|cool|stretch|recovery|pilates|abs|hundred/i.freeze

  # Only these exercise name patterns are acceptable in FM strength sections.
  FM_UPPER_MACHINE_PATTERN = /low row|lat pull|bench press|shoulder press|chest fly|reverse fly|side raise|front raise/i.freeze
  FM_LOWER_MACHINE_PATTERN = /leg press|leg extension|leg curl|hamstring curl|calf raise|squat|deadlift|lunge/i.freeze

  def fix_fm_merge_strength_sections(sections)
    strength_sections = sections.reject do |s|
      s["format"].to_s.in?(FM_STRENGTH_EXEMPT_FORMATS) ||
        s["name"].to_s.match?(FM_STRENGTH_EXEMPT_NAMES)
    end

    return if strength_sections.empty?

    all_exercises = strength_sections.flat_map { |s| Array(s["exercises"]) }.uniq { |e| e["name"] }
    return if all_exercises.empty?

    # Split into upper and lower — pick ONE exercise each
    lower_exercises = all_exercises.select { |e| e["name"].to_s.match?(LOWER_BODY_PATTERN) }
    upper_exercises = all_exercises.reject { |e| e["name"].to_s.match?(LOWER_BODY_PATTERN) }

    # Prefer machine exercises; fall back to first available if none match.
    # If no lower body exercises exist at all, synthesize a fallback so both sections always appear.
    upper_pick = upper_exercises.find { |e| e["name"].to_s.match?(FM_UPPER_MACHINE_PATTERN) } || upper_exercises.first
    lower_pick = lower_exercises.find { |e| e["name"].to_s.match?(FM_LOWER_MACHINE_PATTERN) } ||
                 lower_exercises.first ||
                 { "name" => %w[Leg\ Press Leg\ Extension Leg\ Curl Squats Lunges].sample, "reps" => 10 }

    # Ensure reps: 10
    [ upper_pick, lower_pick ].compact.each { |ex| ex["reps"] = 10 }

    # Remove all existing strength sections
    strength_sections.each { |s| sections.delete(s) }

    # Insert before pilates/abs/cooldown
    insert_at = sections.index { |s| s["name"].to_s.match?(/pilates|abs|hundred|cool|stretch/i) } || sections.size

    new_sections = []
    if upper_pick
      new_sections << {
        "name"      => "Upper Body Strength",
        "format"    => "rounds",
        "rounds"    => 5,
        "rest_secs" => 60,
        "exercises" => [ upper_pick ]
      }
    end
    if lower_pick
      new_sections << {
        "name"      => "Lower Body Strength",
        "format"    => "rounds",
        "rounds"    => 5,
        "rest_secs" => 60,
        "exercises" => [ lower_pick ]
      }
    end

    sections.insert(insert_at, *new_sections)
    @fixes << "FM: strength → #{new_sections.map { |s| "'#{s["name"]}': #{Array(s["exercises"]).first["name"]} 5×10" }.join(", ")}"
  end

  # Strip " Machine" suffix from exercise names in FM strength sections.
  def fix_fm_strip_machine_suffix(sections)
    sections.each do |section|
      next unless section["name"].to_s.match?(/strength/i)
      Array(section["exercises"]).each do |exercise|
        original = exercise["name"].to_s
        cleaned  = original.gsub(/\s+machine\b/i, "").strip
        next if cleaned == original
        exercise["name"] = cleaned
        @fixes << "'#{original}' → '#{cleaned}' (stripped Machine suffix)"
      end
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
