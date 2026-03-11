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
  # Max total work units (reps + calories combined) within a single EMOM circuit minute.
  # Calories count the same as reps for timing purposes.
  EMOM_REP_CAPS = {
    "beginner"     => 10,
    "intermediate" => 15,
    "advanced"     => 20
  }.freeze

  # Cardio machines in circuit EMOMs: hard cap of 10 cal per exercise.
  # On a SkiErg, Air Bike, or Rowing Machine you can't hit more than ~10 cal/min
  # while sharing that minute with other exercises.
  EMOM_CARDIO_CAL_CAP = 10
  CARDIO_MACHINE_PATTERN = /ski|erg|row|bike|assault|air.?bike|concept/i.freeze

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

    fix_for_time_rounds(sections)
    fix_alternating_reps(sections)
    fix_clean_rep_counts(sections)
    fix_rest_secs(sections)
    fix_single_set_sections(sections)
    fix_tabata_exercise_metrics(sections)
    fix_tabata_exercise_notes(sections)
    fix_redundant_section_notes(sections)
    fix_rotating_emom_reps(sections)
    check_cooldown(sections)

    if @main_tag_slug == "functional-muscle"
      fix_fm_remove_activation(sections)
      fix_fm_circuit_emom_reps(sections)
      fix_fm_tabata_remove_non_compounds(sections)
      fix_fm_merge_strength_sections(sections)
      fix_fm_strength_sets(sections)
      fix_fm_warmup(sections)
      fix_fm_strip_machine_suffix(sections)
      fix_fm_trim_metabolic_blocks(sections)
      fix_fm_ensure_abs(sections)
      fix_fm_section_order(sections)
    end

    @data
  end

  private

  # EMOM circuit: total reps per minute must not exceed the difficulty cap.
  # Rotating EMOMs don't have a per-minute rep cap (each exercise fills its own minute).
  # Also enforces a per-exercise calorie cap for cardio machines (max 10 cal).
  def fix_emom_reps(section, idx)
    return if section["emom_style"] == "rotating"
    cap       = EMOM_REP_CAPS[@difficulty] || 20
    exercises = Array(section["exercises"])
    changed   = []

    # First pass: clamp cardio machine calories independently
    exercises.each do |ex|
      next unless ex["calories"].to_i > EMOM_CARDIO_CAL_CAP
      next unless ex["name"].to_s.match?(CARDIO_MACHINE_PATTERN)
      old = ex["calories"]
      ex["calories"] = EMOM_CARDIO_CAL_CAP
      changed << "#{ex["name"]} cal #{old} → #{EMOM_CARDIO_CAL_CAP}"
    end

    # Second pass: scale total if still over cap
    workload_exercises = exercises.select { |e| e["reps"].to_i > 0 || e["calories"].to_i > 0 }
    total = workload_exercises.sum { |e| e["reps"].to_i + e["calories"].to_i }

    if total > cap && workload_exercises.any?
      scale = cap.to_f / total
      workload_exercises.each do |ex|
        if ex["reps"].to_i > 0
          ex["reps"] = [ (ex["reps"].to_i * scale).floor, 1 ].max
        end
        if ex["calories"].to_i > 0
          ex["calories"] = [ (ex["calories"].to_i * scale).floor, 1 ].max
        end
      end
      new_total = workload_exercises.sum { |e| e["reps"].to_i + e["calories"].to_i }
      changed << "total #{total} → #{new_total} (cap: #{cap})"
    end

    @fixes << "EMOM '#{section["name"]}': #{changed.join("; ")}" if changed.any?
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

  # For-time sections with multiple exercises and fewer than 3 rounds are not a
  # meaningful conditioning block — bump to 3 rounds. Single-exercise for_time
  # (e.g. 100 cal row for time) is fine with 1 round.
  def fix_for_time_rounds(sections)
    sections.each do |section|
      next unless section["format"] == "for_time"
      next if Array(section["exercises"]).size <= 1
      next if section["rounds"].to_i >= 3
      old = section["rounds"].to_i
      section["rounds"] = 3
      @fixes << "For-time '#{section["name"]}': rounds #{old} → 3 (multi-exercise for_time needs multiple rounds)"
    end
  end

  # Snap rep and calorie counts to "clean" numbers — even numbers or multiples of 5.
  # Odd, awkward counts like 13 or 7 are artefacts of scaling and look wrong in a workout.
  # Only applies to values >= 4; leaves small counts (1, 2, 3) untouched.
  # Does not touch weight_kg, distance_m, or duration_s.
  def fix_clean_rep_counts(sections)
    sections.each do |section|
      Array(section["exercises"]).each do |ex|
        %w[reps calories].each do |field|
          val = ex[field].to_i
          next if val < 4
          clean = nearest_clean_rep(val)
          next if clean == val
          ex[field] = clean
          @fixes << "'#{ex["name"]}' in '#{section["name"]}': #{field} #{val} → #{clean} (snapped to clean number)"
        end
      end
    end
  end

  def nearest_clean_rep(n)
    return n if n % 2 == 0 || n % 5 == 0
    # Find nearest value that is even or a multiple of 5
    down = (n - 1).downto(1).find { |v| v % 2 == 0 || v % 5 == 0 }
    up   = (n + 1).upto(n + 5).find { |v| v % 2 == 0 || v % 5 == 0 }
    [ down, up ].compact.min_by { |v| (v - n).abs }
  end

  # Any non-exempt section with rounds missing/zero is almost certainly a mistake.
  # - Single-exercise sections with < 3 rounds → 3 rounds
  # - Any section with rounds completely absent (nil) → 3 rounds (LLM forgot to set it)
  # - Unknown/invalid formats get normalised to "rounds"
  # Skips warm-up, cool-down, tabata, emom, amrap, for_time, ladder, mountain.
  SINGLE_SET_EXEMPT   = %w[tabata emom amrap for_time ladder mountain matrix hundred].freeze
  KNOWN_FORMATS       = %w[rounds tabata emom amrap for_time ladder mountain matrix hundred].freeze
  WARMUP_COOLDOWN_PATTERN = /warm|cool|stretch|recovery/i
  ABS_PILATES_PATTERN     = /abs|core|pilates|hundred/i

  def fix_single_set_sections(sections)
    sections.each do |section|
      next if section["name"].to_s.match?(WARMUP_COOLDOWN_PATTERN)
      next if section["name"].to_s.match?(ABS_PILATES_PATTERN)

      fmt = section["format"].to_s

      # Normalise unknown formats to "rounds" so the view renders properly
      unless fmt.in?(KNOWN_FORMATS)
        @fixes << "'#{section["name"]}': unknown format '#{fmt}' → rounds"
        section["format"] = "rounds"
        fmt = "rounds"
      end

      next if fmt.in?(SINGLE_SET_EXEMPT)

      rounds = section["rounds"]
      if rounds.nil? || rounds.to_i.zero?
        # Rounds completely absent — default to 3
        section["rounds"] = 3
        @fixes << "'#{section["name"]}': rounds missing → set to 3"
      elsif rounds.to_i < 3 && Array(section["exercises"]).size == 1
        # Single exercise, too few rounds
        section["rounds"] = 3
        @fixes << "'#{section["name"]}': single exercise with #{rounds} round(s) → 3 rounds"
      end
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


  # Tabata is 20s work / 10s rest — the interval is the constraint, not reps or calories.
  # Strip reps and calories from all tabata exercises; keep weight_kg and distance_m.
  def fix_tabata_exercise_metrics(sections)
    sections.each do |section|
      next unless section["format"] == "tabata"
      Array(section["exercises"]).each do |ex|
        stripped = []
        %w[reps calories distance_m].each do |field|
          if ex[field].present?
            stripped << "#{field}: #{ex[field]}"
            ex.delete(field)
          end
        end
        next if stripped.empty?
        @fixes << "Tabata '#{section["name"]}': removed #{stripped.join(", ")} from '#{ex["name"]}' — 20s burst, no metric needed"
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

  # Strip leading "N sets of N reps at Xkg" sentences from section notes — that
  # information is already shown structurally in the section header and exercise rows.
  REDUNDANT_NOTE_PATTERN = /\A\d+\s+sets?\s+of\s+\d+[^.]*\.\s*/i

  def fix_redundant_section_notes(sections)
    sections.each do |section|
      next unless section["notes"].present?
      cleaned = section["notes"].sub(REDUNDANT_NOTE_PATTERN, "").strip
      next if cleaned == section["notes"]
      if cleaned.empty?
        section.delete("notes")
      else
        section["notes"] = cleaned
      end
      @fixes << "'#{section["name"]}': stripped redundant set/rep restatement from section notes"
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

    # Cardio machines should use calories: 100, not reps: 100
    if ex["name"].to_s.match?(CARDIO_MACHINE_PATTERN)
      if ex["reps"].to_i > 0
        ex["calories"] = 100
        ex.delete("reps")
        @fixes << "Hundred '#{section["name"]}': #{ex["name"]} is a cardio machine — reps → calories: 100"
      elsif ex["calories"].to_i != 100
        old = ex["calories"]
        ex["calories"] = 100
        @fixes << "Hundred '#{section["name"]}': calories #{old} → 100"
      end
    else
      unless ex["reps"].to_i == 100
        old = ex["reps"]
        ex["reps"] = 100
        @fixes << "Hundred '#{section["name"]}': reps #{old} → 100"
      end
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

  # Rotating EMOM exercises fill the full minute — reps, calories, distance, and duration
  # must not be set. Also strip notes that are just minute-assignment labels (e.g. "Min 1, 3, 5:").
  # These are redundant — exercises just rotate in order; the athlete doesn't need minute callouts.
  ROTATING_EMOM_NOTE_JUNK = /\A\s*min(?:ute)?s?\s+[\d,\s]+[:–\-]/i.freeze

  def fix_rotating_emom_reps(sections)
    sections.each do |section|
      next unless section["format"] == "emom" && section["emom_style"] == "rotating"
      Array(section["exercises"]).each do |ex|
        stripped = []

        %w[reps calories distance_m duration_s].each do |field|
          if ex[field].present?
            stripped << "#{field}: #{ex[field]}"
            ex.delete(field)
          end
        end

        # Strip minute-assignment prefix from notes (e.g. "Min 1, 3, 5, 7: explosive snatch")
        if ex["notes"].to_s.match?(ROTATING_EMOM_NOTE_JUNK)
          cleaned = ex["notes"].sub(ROTATING_EMOM_NOTE_JUNK, "").strip.sub(/\A[,.\s]+/, "").strip
          if cleaned.present?
            ex["notes"] = cleaned
          else
            ex.delete("notes")
          end
          stripped << "minute-assignment note"
        end

        next if stripped.empty?
        @fixes << "Continuous Circuit '#{section["name"]}': cleaned '#{ex["name"]}' (#{stripped.join(", ")})"
      end
    end
  end

  # FM circuit EMOMs (every-2-min style): reps must be multiples of 5, minimum 5 per
  # exercise, and at least 25 total across all exercises. If total < 25, scale up
  # proportionally (preserving ratios) until the minimum is met.
  FM_CIRCUIT_EMOM_MIN_TOTAL = 25

  def fix_fm_circuit_emom_reps(sections)
    sections.each do |section|
      next unless section["format"] == "emom" && section["emom_style"] != "rotating"
      exercises = Array(section["exercises"]).select { |e| e["reps"].to_i > 0 }
      next if exercises.empty?

      # Step 1: snap each to nearest multiple of 5, min 5
      exercises.each do |ex|
        ex["reps"] = [ ((ex["reps"].to_i / 5.0).round * 5), 5 ].max
      end

      # Step 2: enforce minimum total of 25
      total = exercises.sum { |e| e["reps"].to_i }
      if total < FM_CIRCUIT_EMOM_MIN_TOTAL
        # Scale up proportionally, keeping each as a multiple of 5, min 5
        scale = FM_CIRCUIT_EMOM_MIN_TOTAL.to_f / total
        exercises.each do |ex|
          ex["reps"] = [ ((ex["reps"].to_i * scale / 5.0).ceil * 5), 5 ].max
        end
        new_total = exercises.sum { |e| e["reps"].to_i }
        @fixes << "FM circuit EMOM '#{section["name"]}': scaled up reps (total #{total} → #{new_total}, minimum #{FM_CIRCUIT_EMOM_MIN_TOTAL} required)"
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
      next if section["name"].to_s.match?(ABS_PILATES_PATTERN)

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
  FM_STRENGTH_EXEMPT_NAMES   = /warm|cool|stretch|recovery|pilates|abs|core|hundred/i.freeze

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

  # FM: if no abs/core section is present, synthesise one before the cool-down.
  # Rotates through a small pool so fallback workouts have some variety.
  FM_ABS_FALLBACK_POOL = [
    [ { "name" => "Sit-ups", "reps" => 20 }, { "name" => "Leg raises", "reps" => 20 }, { "name" => "Bicycle crunches", "reps" => 30 }, { "name" => "Alternating toe touches", "reps" => 30 } ],
    [ { "name" => "V-ups", "reps" => 25 }, { "name" => "Russian twists", "reps" => 25 }, { "name" => "Overhead crunches", "reps" => 25 }, { "name" => "Flutter kicks", "reps" => 25 } ],
    [ { "name" => "Crunches", "reps" => 25 }, { "name" => "Leg raises", "reps" => 25 }, { "name" => "Plank shoulder taps", "reps" => 25 }, { "name" => "Dead bugs", "reps" => 25 } ]
  ].freeze

  def fix_fm_ensure_abs(sections)
    has_abs = sections.any? { |s| s["name"].to_s.match?(ABS_PILATES_PATTERN) || s["format"] == "hundred" }
    return if has_abs

    exercises = FM_ABS_FALLBACK_POOL.sample
    abs_section = {
      "name"      => "Abs Finisher",
      "format"    => "straight",
      "exercises" => exercises
    }

    insert_at = sections.index { |s| s["name"].to_s.match?(/cool|stretch/i) } || sections.size
    sections.insert(insert_at, abs_section)
    @fixes << "FM: synthesised Abs Finisher (100 reps) — LLM omitted abs section"
  end

  # FM: enforce the metabolic time budget.
  # Fixed sections (warm-up 5 + upper strength 8 + lower strength 8 + abs 5 + cool-down 4) = 30 min.
  # Remaining budget = duration_mins - 30. If metabolic blocks exceed this, remove from the end.
  FM_BLOCK_MINUTES = {
    "tabata"   => 6,
    "mountain" => 10,
    "ladder"   => 12,
    "hundred"  => 5,
  }.freeze
  FM_FIXED_MINS = 30

  def fix_fm_trim_metabolic_blocks(sections)
    budget = (@duration_mins || 60) - FM_FIXED_MINS
    return if budget <= 0

    metabolic = sections.reject do |s|
      name = s["name"].to_s
      name.match?(WARMUP_COOLDOWN_PATTERN) ||
        name.match?(ABS_PILATES_PATTERN) ||
        name.match?(/strength/i)
    end

    total = metabolic.sum { |s| fm_block_estimated_mins(s) }
    return if total <= budget

    while total > budget && metabolic.size > 1
      removed = metabolic.pop
      removed_mins = fm_block_estimated_mins(removed)
      sections.delete(removed)
      total -= removed_mins
      @fixes << "FM time budget: removed '#{removed["name"]}' (#{removed_mins} min) — over #{budget} min metabolic budget"
    end
  end

  def fm_block_estimated_mins(section)
    fmt = section["format"].to_s
    return FM_BLOCK_MINUTES[fmt] if FM_BLOCK_MINUTES.key?(fmt)
    if fmt == "emom"
      dm = section["duration_mins"].to_i
      return dm > 0 ? dm : 10
    end
    10
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

  # FM: enforce section order — warm-up → metabolic → upper strength → lower strength → abs → cool-down.
  # Pulls any abs/pilates sections out and reinserts them just before the cool-down.
  def fix_fm_section_order(sections)
    abs_sections = sections.select { |s| s["name"].to_s.match?(ABS_PILATES_PATTERN) || s["format"] == "hundred" }
    return if abs_sections.empty?

    cooldown_idx = sections.index { |s| s["name"].to_s.match?(/cool|stretch/i) }
    target_idx   = cooldown_idx || sections.size

    # Check if all abs sections are already just before the cool-down — if so, nothing to do
    abs_indices = abs_sections.map { |s| sections.index(s) }
    expected_start = target_idx - abs_sections.size
    return if abs_indices == (expected_start...(expected_start + abs_sections.size)).to_a

    abs_sections.each { |s| sections.delete(s) }
    # Recalculate insert position after deletion
    new_target = sections.index { |s| s["name"].to_s.match?(/cool|stretch/i) } || sections.size
    sections.insert(new_target, *abs_sections)
    @fixes << "FM: moved abs section(s) to just before cool-down"
  end

  # Warn if the last section doesn't look like a cool-down.
  def check_cooldown(sections)
    last = sections.last
    return if last.nil?
    return if last["name"]&.downcase&.match?(/cool|stretch|recovery/)
    @warnings << "No cool-down detected — last section is '#{last["name"]}'"
  end
end
