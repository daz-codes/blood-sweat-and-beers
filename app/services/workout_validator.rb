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
        fix_emom_reps(section, idx)
      when "tabata"
        fix_tabata_duration(section, idx)
      when "ladder", "mountain"
        fix_ladder_step(section, idx)
      end
    end

    fix_alternating_reps(sections)
    check_cooldown(sections)

    @data
  end

  private

  # EMOM: total reps per minute must not exceed the difficulty cap.
  # Only rep-based exercises count — duration_s / distance_m / calories are time/distance
  # constraints, not rep counts, so they don't contribute to the per-minute rep total.
  # Scales all rep exercises proportionally, flooring each to at least 1.
  def fix_emom_reps(section, idx)
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


  # Warn if the last section doesn't look like a cool-down.
  def check_cooldown(sections)
    last = sections.last
    return if last.nil?
    return if last["name"]&.downcase&.match?(/cool|stretch|recovery/)
    @warnings << "No cool-down detected — last section is '#{last["name"]}'"
  end
end
