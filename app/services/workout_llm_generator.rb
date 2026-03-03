require "net/http"
require "json"

# WorkoutLLMGenerator uses Claude Haiku (via Anthropic API tool use) to generate
# a structured workout plan based on community context and user preferences.
#
# Usage:
#   workout = WorkoutLLMGenerator.call(
#     user:          current_user,
#     tag_ids:       [1, 3],
#     duration_mins: 30,
#     difficulty:    "intermediate"
#   )
#
# Returns a persisted Workout record or raises WorkoutGenerationError.
class WorkoutLLMGenerator
  # Maps tag slugs/names to context files in app/llm_context/
  CONTEXT_TAG_MAP = {
    "hyrox"        => "hyrox.md",
    "deka"         => "deka_fit.md",
    "deka-fit"     => "deka_fit.md",
    "deka-strong"  => "deka_strong.md",
    "deka-mile"    => "deka_mile.md",
    "deka-atlas"   => "deka_atlas.md",
    "dirty-dozen"  => "dirty_dozen.md",
    "swimming"     => "swimming.md",
    "swim"         => "swimming.md",
    "running"      => "running.md",
    "run"          => "running.md",
  }.freeze

  CONTEXT_DIR = Rails.root.join("app", "llm_context").freeze
  class WorkoutGenerationError < StandardError; end

  API_URI = URI("https://api.anthropic.com/v1/messages").freeze
  MODEL   = "claude-haiku-4-5-20251001".freeze

  TOOL_DEFINITION = {
    name: "create_workout",
    description: "Create a structured workout plan in the required JSON format.",
    input_schema: {
      type: "object",
      required: %w[name workout_type duration_mins difficulty structure],
      properties: {
        name:          { type: "string",  description: "Punchy, imaginative workout name (2-4 words). Use vivid, evocative language — like a nickname you'd give a brutal session. Examples: 'Farmer's Walk Mayhem', 'Bicep Blast', 'Death by Burpees', 'Iron Lung Sunday', 'The Grind', 'Lactic Acid Special'. Avoid generic names like 'Full Body Workout'." },
        workout_type:  { type: "string",  enum: Workout::TYPES },
        duration_mins: { type: "integer", description: "Total workout duration in minutes" },
        difficulty:    { type: "string",  enum: Workout::DIFFICULTIES },
        structure: {
          type: "object",
          required: ["sections"],
          properties: {
            goal: { type: "string", description: "One-sentence coaching cue for the session" },
            sections: {
              type: "array",
              items: {
                type: "object",
                required: %w[name format],
                properties: {
                  name:               { type: "string" },
                  format:             { type: "string", enum: %w[straight amrap rounds emom tabata for_time ladder mountain], description: "straight=sets with rest, rounds=multiple rounds of the same set, amrap=as many rounds as possible in a time cap, emom=every minute on the minute, tabata=20s work/10s rest×8, for_time=complete prescribed reps/distance as fast as possible (record finishing time), ladder/mountain=reps/distance change each round" },
                  duration_mins:      { type: "integer" },
                  rounds:             { type: "integer" },
                  rest_secs:          { type: "integer" },
                  notes:              { type: "string" },
                  varies:             { type: "string", enum: %w[reps calories kg distance_m], description: "What changes each rung (ladder/mountain only). CRITICAL: every exercise in this section must share this metric — do not mix rep-based, distance-based, and calorie-based exercises in the same ladder/mountain." },
                  start:              { type: "number", description: "Starting value for ladder/mountain" },
                  end:                { type: "number", description: "Ending value for ladder/mountain" },
                  peak:               { type: "number", description: "Peak value for mountain sections" },
                  step:               { type: "number", description: "Increment between rungs. Must be appropriate for the metric: reps → 1–5, distance_m → 10–20 (never less than 10), calories → 5–10 (never less than 5), kg → 5–10." },
                  rest_between_rungs: { type: "integer", description: "Rest in seconds between each rung (optional)" },
                  exercises: {
                    type: "array",
                    items: {
                      type: "object",
                      required: ["name"],
                      properties: {
                        name:        { type: "string" },
                        reps:        { type: "integer" },
                        calories:    { type: "integer", description: "Calories target (e.g. assault bike, rower, ski erg)" },
                        distance_m:  { type: "integer" },
                        duration_s:  { type: "integer" },
                        weight_kg:   { type: "number" },
                        notes:       { type: "string" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }.freeze

  def self.call(user:, duration_mins:, difficulty:, main_tag_id: nil, minor_tag_ids: [], tag_ids: [], source_workout: nil)
    new(user: user, main_tag_id: main_tag_id, minor_tag_ids: minor_tag_ids, tag_ids: tag_ids, duration_mins: duration_mins, difficulty: difficulty, source_workout: source_workout).call
  end

  def initialize(user:, duration_mins:, difficulty:, main_tag_id: nil, minor_tag_ids: [], tag_ids: [], source_workout: nil)
    @user           = user
    @main_tag       = main_tag_id.present? ? Tag.find_by(id: main_tag_id) : nil
    @minor_tags     = Tag.where(id: Array(minor_tag_ids).map(&:to_i).reject(&:zero?))
    # tag_ids kept for backwards compat (remix path uses source workout tags directly)
    @tag_ids        = tag_ids.any? ? Array(tag_ids).map(&:to_i).reject(&:zero?) : ([@main_tag&.id] + @minor_tags.map(&:id)).compact
    @duration_mins  = duration_mins.to_i
    @difficulty     = difficulty
    @source_workout = source_workout
  end

  def call
    if @source_workout
      tag_names    = @source_workout.tags.map(&:name)
      prompt       = build_remix_prompt
      workout_data = call_llm(prompt)
      create_workout(workout_data, tag_names)
    else
      context_workouts = fetch_context
      prompt           = build_prompt(context_workouts)
      workout_data     = call_llm(prompt)
      all_tag_names    = ([@main_tag&.name] + @minor_tags.map(&:name)).compact
      create_workout(workout_data, all_tag_names)
    end
  end

  private

  def fetch_context
    ids = @tag_ids.any? ? Workout.most_liked_with_tags(@tag_ids, limit: 5).pluck(:id) : []
    if ids.size < 3
      ids = Workout.left_joins(:workout_likes)
                   .group(:id)
                   .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
                   .limit(5)
                   .pluck(:id)
    end
    return [] if ids.empty?
    Workout.where(id: ids).includes(:tags)
  end

  def build_prompt(context_workouts)
    main_name  = @main_tag&.name || "general fitness"
    minor_str  = @minor_tags.map(&:name).join(", ")

    task_sentence = if minor_str.present?
      "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} workout that focuses on the following aspects: #{minor_str}."
    else
      "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} workout."
    end

    sections = []

    sections << <<~BASE
      You are a personal trainer specialising in writing fun and exciting workouts that improve people's overall fitness.

      #{task_sentence}
    BASE

    sport_context = load_sport_context([@main_tag&.name].compact)
    sections << sport_context if sport_context.present?

    # Only include community workouts when there's no sport-specific context —
    # otherwise they add noise that overwhelms the athlete constraints.
    if sport_context.blank? && context_workouts.any?
      context_json = context_workouts.map do |w|
        { name: w.name, tags: w.tags.map(&:name), duration_mins: w.duration_mins,
          difficulty: w.difficulty, structure: w.structure }
      end.to_json
      sections << <<~COMMUNITY
        Here are #{context_workouts.size} popular community workouts for inspiration:
        #{context_json}
      COMMUNITY
    end

    # Athlete context goes last before rules — closest to generation, hardest to ignore.
    user_context = build_user_context
    sections << user_context if user_context.present?

    sport_rule  = sport_purity_rule
    pace_limits = pace_limit_rule

    sections << <<~RULES
      Use the create_workout tool. Requirements:
      - Total duration close to #{@duration_mins} minutes
      - Sections: warm-up, main set (can be split into multiple sections), optional finisher
      - Warm-up: easy cardio + a few bodyweight movements to loosen up — keep it brief
      - Finisher: something punchy and challenging to end on
      - Be specific with reps, distances, and weights
      - Give it a punchy, memorable name — something a gym community would actually call it (CrossFit-style), not a generic description
      #{sport_rule}
      #{pace_limits}
      - FORMAT SELECTION — choose the best format for each section. Actively vary formats across sections (do not use the same format for every section):
        * tabata — high-intensity cardio bursts or bodyweight finishers. 20s on / 10s off × 8 rounds (~4 min). Great for: assault bike, ski erg, burpees, KB swings, box jumps, jump rope. Do NOT add reps or calories to tabata exercises — the 20s interval is the constraint. You may specify distance_m or weight_kg where relevant.
        * emom — strength, skill work, or paced conditioning. Each minute: do the prescribed reps, rest for the remainder. E.g. "EMOM 10 min: 5 thrusters + 5 pull-ups". Great for: barbell work, gymnastics, moderate cardio intervals.
        * amrap — clock-driven main set. Complete as many rounds as possible. E.g. "AMRAP 12 min: 10 KB swings + 10 box jumps + 200m run". Great for: mixed modal circuits.
        * for_time — single-effort challenge, record finishing time. E.g. "100 wall balls for time" or "5 rounds: 400m run + 20 push-ups". Great for: benchmark efforts, race-pace work.
        * rounds — structured circuit with planned rest. Good for strength, controlled conditioning with recovery.
        * ladder / mountain — rep or distance progression each rung. ONLY when all exercises share the same metric AND the step size is realistic:
          - reps: step 1–5. E.g. start:10 end:1 step:1 = 10,9,8...1 reps.
          - calories: step 5–10. E.g. start:20 end:5 step:5 = 20,15,10,5 cal.
          - distance_m: step 10–20. E.g. start:40 end:20 step:10 = 40m,30m,20m.
          - mountain: ascend then descend. E.g. start:5 peak:15 end:5 step:5 = 5,10,15,10,5 reps.
          - INVALID: mixing reps, distance, and calorie exercises in the same ladder.
        * straight — fixed sets with rest. Use for simple warm-ups or isolated exercises.
      RULES

    sections.join("\n")
  end

  # Injects a hard pace ceiling into the rules section so it's fresh immediately
  # before the LLM generates the workout — not buried in the athlete context above.
  # Expresses pace limits as whole-distance times (not just splits) so the model
  # never has to convert — it can read the time directly for whatever distance it picks.
  def pace_limit_rule
    pbs = @user.personal_bests || {}
    lines = []

    ski_split = if pbs["ski_500m"]
      pbs["ski_500m"].to_i
    elsif pbs["ski_2000m"]
      pbs["ski_2000m"].to_i / 4
    end
    if ski_split
      lines << "SkiErg — never faster than: 500m=#{fmt_secs(ski_split)} | 1000m=#{fmt_secs(ski_split * 2)} | 2000m=#{fmt_secs(ski_split * 4)} (these are MAX; programme easier for aerobic work)"
    end

    row_split = if pbs["row_500m"]
      pbs["row_500m"].to_i
    elsif pbs["row_2000m"]
      pbs["row_2000m"].to_i / 4
    end
    if row_split
      lines << "Row — never faster than: 500m=#{fmt_secs(row_split)} | 1000m=#{fmt_secs(row_split * 2)} | 2000m=#{fmt_secs(row_split * 4)} (these are MAX; programme easier for aerobic work)"
    end

    run_pace = if pbs["run_5km"]
      pbs["run_5km"].to_i / 5
    elsif pbs["run_10km"]
      pbs["run_10km"].to_i / 10
    end
    if run_pace
      lines << "Running — never faster than: 1km=#{fmt_secs(run_pace)} | 5km=#{fmt_secs(run_pace * 5)} | 10km=#{fmt_secs(run_pace * 10)} (these are MAX; programme easier for aerobic work)"
    end

    swim_split = if pbs["swim_100m_fc"]
      pbs["swim_100m_fc"].to_i
    elsif pbs["swim_400m"]
      pbs["swim_400m"].to_i / 4
    end
    if swim_split
      lines << "Swim — never faster than: 100m=#{fmt_secs(swim_split)} | 400m=#{fmt_secs(swim_split * 4)} | 1500m=#{fmt_secs(swim_split * 15)} (these are MAX)"
    end

    return "" if lines.empty?

    "- Athlete pace limits (HARD LIMITS — do not prescribe any time faster than these):\n#{lines.map { |l| "    * #{l}" }.join("\n")}"
  end

  # Returns a bullet-point rule if the main/minor tags indicate a single-sport session
  # or an explicit exclusion (e.g. "no-run" minor tag for a Hyrox gym-only session).
  def sport_purity_rule
    main_slug   = @main_tag&.slug || ""
    minor_slugs = @minor_tags.map(&:slug)

    no_run  = minor_slugs.any? { |s| s.in?(%w[no-run no-running no-runs]) }
    is_run  = !no_run && (main_slug.in?(%w[running run]) || minor_slugs.any? { |s| s.include?("run") || %w[tempo sprint intervals 5k 10k marathon trail].include?(s) })
    is_swim = main_slug.in?(%w[swimming swim]) || minor_slugs.any? { |s| s.include?("swim") || s.include?("pool") || s == "open-water" }

    if no_run
      "- Do NOT include any running in this session. Replace any running segments with rowing, SkiErg, bike erg, or other non-running cardio."
    elsif is_run
      "- This is a running session — use ONLY running distances and dynamic movement/drills. Do NOT add gym exercises, weights, or machines."
    elsif is_swim
      "- This is a swimming session — use ONLY swimming strokes, drills, and kick/pull sets. Do NOT add gym exercises."
    else
      ""
    end
  end

  def build_remix_prompt
    source_json = {
      tags:          @source_workout.tags.map(&:name),
      duration_mins: @source_workout.duration_mins,
      difficulty:    @source_workout.difficulty,
      structure:     @source_workout.structure
    }.to_json

    <<~PROMPT.strip
      You are a personal trainer specialising in writing fun workouts that athletes enjoy and improves their fitness.

      If the user is doing a run, don't add any gym exercises, just use running and dynamic stretches.

      If the user is doing a swim, only use swimming drills and strokes.

      Generate a #{@duration_mins}-minute #{@difficulty} workout inspired by this existing workout:
      #{source_json}

      Draw on its movement patterns, energy systems, and overall feel — but this must be a genuinely different session. Swap exercises, change rep schemes, restructure sections, or shift the emphasis. Someone who does both workouts back-to-back should feel like they trained differently.

      Use the create_workout tool. Requirements:
      - Total duration close to #{@duration_mins} minutes
      - Same training focus as the source but a clearly distinct session
      - Be specific with reps, distances, and weights
      - workout_type should always be "custom"
      - The name MUST be completely original — do NOT reuse or rephrase "#{@source_workout.name}"
      - You may use ladder or mountain sections for variety, but ONLY when all exercises share the same metric AND the step size is realistic:
        * reps: step 1–5. E.g. start:10 end:1 step:1 = 10,9,8...1 reps.
        * calories: step 5–10. E.g. start:20 end:5 step:5 = 20,15,10,5 cal.
        * distance_m: step 10–20. E.g. start:40 end:20 step:10 = 40m,30m,20m.
        * kg: step 5–10. E.g. start:60 end:40 step:10 = 60,50,40 kg.
        * INVALID: mixing metrics, or distance steps of 1–5m, or calorie steps of 1–4. Use rounds or straight instead.
    PROMPT
  end

  # Builds a coaching brief to inject into the prompt.
  def build_user_context
    sections = []

    # Opening sentence: natural description of the athlete
    descriptor = build_athlete_descriptor
    sections << descriptor if descriptor.present?

    # Training environment
    env_parts = []
    if @user.run_preference.present?
      env_parts << "#{@user.run_preference} running#{" (always programme 1% incline)" if @user.run_preference == "treadmill"}."
    end
    env_parts << "#{@user.pool_length} pool" if @user.pool_length.present?
    sections << "Training environment: #{env_parts.join(", ")}." if env_parts.any?

    if @user.equipment.present?
      readable = @user.equipment.map(&:humanize).join(", ")
      sections << "Available equipment: #{readable}."
    end

    benchmarks = format_benchmarks
    sections << benchmarks if benchmarks.present?

    return nil if sections.empty?

    "## Athlete Context\n#{sections.join("\n")}\n"
  end

  # Produces a natural opening sentence describing the athlete.
  def build_athlete_descriptor
    parts = []

    age_gender = []
    age_gender << "#{@user.age}-year-old" if @user.age.present?
    gender_label = { "male" => "male", "female" => "female", "non_binary" => "non-binary" }[@user.gender]
    age_gender << gender_label if gender_label
    parts << age_gender.join(" ") if age_gender.any?

    physical = []
    physical << "#{@user.height_cm}cm" if @user.height_cm.present?
    physical << "#{@user.weight_kg.to_f.round(1)}kg" if @user.weight_kg.present?

    return nil if parts.empty? && physical.empty?

    if parts.any? && physical.any?
      "The athlete is a #{parts.join(" ")} (#{physical.join(", ")})."
    elsif parts.any?
      "The athlete is a #{parts.join(" ")}."
    else
      "The athlete is #{physical.join(", ")}."
    end
  end

  # Builds a unified benchmarks block giving the LLM raw PBs plus scaling principles.
  # The LLM derives contextually appropriate paces and weights from these rather than
  # receiving pre-computed fixed bands.
  def format_benchmarks
    pbs = @user.personal_bests || {}
    bw  = @user.weight_kg.to_f
    has_cardio   = false
    has_strength = false

    cardio_lines    = []
    strength_lines  = []
    other_pb_lines  = []

    # ── Cardio PBs — inline pace guides per sport ───────────────────────────
    # Each line gives: PB → easy → threshold → max sustained → sprint note
    # Pre-computed so the LLM never has to calculate percentages.

    # Row — split per 500m
    row_pb = if pbs["row_500m"]
      pbs["row_500m"].to_i
    elsif pbs["row_1000m"]
      pbs["row_1000m"].to_i / 2
    elsif pbs["row_2000m"]
      pbs["row_2000m"].to_i / 4
    end
    if row_pb
      label = pbs["row_500m"] ? "500m" : (pbs["row_1000m"] ? "1000m" : "2000m")
      raw   = pbs["row_500m"] || pbs["row_1000m"] || pbs["row_2000m"]
      cardio_lines << "Row (PB #{label} #{fmt_secs(raw.to_i)}, = #{fmt_secs(row_pb)}/500m split): " \
                      "easy #{fmt_secs((row_pb * 1.35).to_i)}/500m | threshold #{fmt_secs((row_pb * 1.08).to_i)}/500m | " \
                      "max sustained #{fmt_secs(row_pb)}/500m | sprints can go below max"
    end

    # SkiErg — split per 500m
    ski_pb = if pbs["ski_500m"]
      pbs["ski_500m"].to_i
    elsif pbs["ski_2000m"]
      pbs["ski_2000m"].to_i / 4
    end
    if ski_pb
      label = pbs["ski_500m"] ? "500m" : "2000m"
      raw   = pbs["ski_500m"] || pbs["ski_2000m"]
      cardio_lines << "SkiErg (PB #{label} #{fmt_secs(raw.to_i)}, = #{fmt_secs(ski_pb)}/500m): " \
                      "easy #{fmt_secs((ski_pb * 1.35).to_i)}/500m | threshold #{fmt_secs((ski_pb * 1.08).to_i)}/500m | " \
                      "max sustained #{fmt_secs(ski_pb)}/500m | sprints (≤30s) can go below max"
    end

    # Running — per km pace
    run_pb_pace = if pbs["run_5km"]
      pbs["run_5km"].to_i / 5
    elsif pbs["run_10km"]
      pbs["run_10km"].to_i / 10
    elsif pbs["run_half_marathon"]
      pbs["run_half_marathon"].to_i / 21
    end
    if run_pb_pace
      ref_dist = pbs["run_5km"] ? "5km #{fmt_secs(pbs["run_5km"].to_i)}" : (pbs["run_10km"] ? "10km #{fmt_secs(pbs["run_10km"].to_i)}" : "half marathon #{fmt_secs(pbs["run_half_marathon"].to_i)}")
      cardio_lines << "Run (PB #{ref_dist}, = #{fmt_secs(run_pb_pace)}/km): " \
                      "easy #{fmt_secs((run_pb_pace * 1.30).to_i)}/km | threshold #{fmt_secs((run_pb_pace * 1.05).to_i)}/km | " \
                      "max sustained #{fmt_secs(run_pb_pace)}/km | sprints (≤400m) can go below max"
    end
    cardio_lines << "Run 1 mile PB: #{fmt_secs(pbs["run_1mile"].to_i)}" if pbs["run_1mile"] && !run_pb_pace
    cardio_lines << "Run 1.5 miles (Cooper) PB: #{fmt_secs(pbs["run_1_5mile"].to_i)}" if pbs["run_1_5mile"] && !run_pb_pace

    # Swimming — per 100m pace
    swim_pb_pace = if pbs["swim_100m_fc"]
      pbs["swim_100m_fc"].to_i
    elsif pbs["swim_400m"]
      pbs["swim_400m"].to_i / 4
    elsif pbs["swim_1500m"]
      pbs["swim_1500m"].to_i / 15
    end
    if swim_pb_pace
      ref = pbs["swim_100m_fc"] ? "100m FC #{fmt_secs(pbs["swim_100m_fc"].to_i)}" : (pbs["swim_400m"] ? "400m #{fmt_secs(pbs["swim_400m"].to_i)}" : "1500m #{fmt_secs(pbs["swim_1500m"].to_i)}")
      cardio_lines << "Swim (PB #{ref}, = #{fmt_secs(swim_pb_pace)}/100m): " \
                      "easy #{fmt_secs((swim_pb_pace * 1.28).to_i)}/100m | threshold #{fmt_secs((swim_pb_pace * 1.07).to_i)}/100m | " \
                      "max sustained #{fmt_secs(swim_pb_pace)}/100m | sprints (25–50m) can go below max"
    end
    cardio_lines << "Swim 1 mile PB: #{fmt_secs(pbs["swim_1mile"].to_i)}" if pbs["swim_1mile"]

    # Assault / Echo Bike
    if pbs["assault_bike_50cal"]
      cardio_lines << "Assault bike 50cal PB: #{fmt_secs(pbs["assault_bike_50cal"].to_i)}"
    end
    if pbs["assault_bike_100cal"]
      cardio_lines << "Assault bike 100cal PB: #{fmt_secs(pbs["assault_bike_100cal"].to_i)}"
    end

    has_cardio = cardio_lines.any?

    # ── Strength PBs ────────────────────────────────────────────────────────
    { "bench_1rm" => "Bench press 1RM", "squat_1rm" => "Back squat 1RM",
      "deadlift_1rm" => "Deadlift 1RM", "clean_jerk_1rm" => "Clean & Jerk 1RM",
      "snatch_1rm" => "Snatch 1RM" }.each do |key, label|
      next unless pbs[key]
      strength_lines << "#{label}: #{pbs[key].to_f.round(1)}kg"
      has_strength = true
    end

    # ── Other PBs (functional tests, bodyweight) ─────────────────────────────
    {
      "press_ups_2min" => "Press-ups (2 min)", "pull_ups_max" => "Max pull-ups",
      "burpees_1min"   => "Burpees (1 min)"
    }.each do |key, label|
      next unless pbs[key]
      other_pb_lines << "#{label}: #{pbs[key].to_i} reps"
    end
    {
      "floor_to_ceiling_30" => "30 floor-to-ceilings",
      "thrusters_50" => "50 thrusters",
      "wall_balls_100" => "100 wall balls",
      "hyrox_race" => "Hyrox race",
      "deka_fit" => "Deka Fit"
    }.each do |key, label|
      next unless pbs[key]
      secs = pbs[key].to_i
      h, rem = secs.divmod(3600)
      m, s   = rem.divmod(60)
      t = h > 0 ? "#{h}:#{m.to_s.rjust(2, "0")}:#{s.to_s.rjust(2, "0")}" : "#{m}:#{s.to_s.rjust(2, "0")}"
      other_pb_lines << "#{label}: #{t}"
    end

    # ── Assemble ─────────────────────────────────────────────────────────────
    return nil if cardio_lines.empty? && strength_lines.empty? && other_pb_lines.empty? && bw.zero?

    out = []

    if has_cardio
      out << "Cardio pace guide (use these exact paces — do not invent times outside these ranges):\n" \
             "#{cardio_lines.map { |l| "  - #{l}" }.join("\n")}"
    end

    if has_strength || bw > 0
      strength_block = []
      strength_block.concat(strength_lines)
      strength_block << "Body weight: #{bw.round(1)}kg" if bw > 0

      out << <<~STRENGTH.strip
        Strength benchmarks (use to calibrate all weighted exercises):
        #{strength_block.map { |l| "  - #{l}" }.join("\n")}
          Rep-to-weight guide: 3–5 reps ≈ 85–90% 1RM | 8–10 reps ≈ 75% 1RM | 15 reps ≈ 68% 1RM | 20+ reps ≈ 60–65% 1RM. Carries: farmer's carry typically 30–40% of deadlift 1RM per hand; sled/sandbag ≈ 60–80% body weight.
      STRENGTH
    end

    unless other_pb_lines.empty?
      out << "Other PBs:\n#{other_pb_lines.map { |l| "  - #{l}" }.join("\n")}"
    end

    out.join("\n")
  end

  def fmt_secs(secs)
    m = secs / 60
    s = secs % 60
    "#{m}:#{s.to_s.rjust(2, "0")}"
  end

  # Loads sport-specific context files based on the workout's tags.
  # Deduplicates — if multiple tags map to the same file, it's only included once.
  def load_sport_context(tag_names)
    files_to_load = tag_names.filter_map do |name|
      CONTEXT_TAG_MAP[name.downcase.parameterize]
    end.uniq

    return nil if files_to_load.empty?

    content = files_to_load.filter_map do |filename|
      path = CONTEXT_DIR.join(filename)
      next unless path.exist?
      File.read(path)
    end.join("\n\n---\n\n")

    return nil if content.blank?

    "## Sport-Specific Guidelines\n#{content}"
  end

  def call_llm(prompt)
    api_key = ENV.fetch("ANTHROPIC_API_KEY") { raise WorkoutGenerationError, "ANTHROPIC_API_KEY not configured" }

    body = {
      model:       MODEL,
      max_tokens:  4096,
      tools:       [ TOOL_DEFINITION ],
      tool_choice: { type: "any" },
      messages:    [ { role: "user", content: prompt } ]
    }

    http            = Net::HTTP.new(API_URI.host, API_URI.port)
    http.use_ssl    = true
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Post.new(API_URI.path)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = api_key
    request["anthropic-version"] = "2023-06-01"
    request.body = body.to_json

    response = http.request(request)
    unless response.code.to_i == 200
      case response.code.to_i
      when 529
        raise WorkoutGenerationError, "The AI service is currently overloaded. Please try again in a moment."
      when 429
        raise WorkoutGenerationError, "Too many requests. Please wait a moment and try again."
      when 500, 502, 503
        raise WorkoutGenerationError, "The AI service is temporarily unavailable. Please try again shortly."
      else
        raise WorkoutGenerationError, "Failed to generate workout (error #{response.code}). Please try again."
      end
    end

    parsed     = JSON.parse(response.body)
    tool_block = parsed["content"].find { |b| b["type"] == "tool_use" }
    raise WorkoutGenerationError, "No workout returned by LLM" unless tool_block

    tool_block["input"]
  end

  def create_workout(data, tag_names)
    tags = tag_names.map do |name|
      Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name }
    end

    workout = Workout.create!(
      user:          @user,
      name:          data["name"].presence || "Generated Workout",
      workout_type:  Workout::TYPES.include?(data["workout_type"]) ? data["workout_type"] : "custom",
      duration_mins: data["duration_mins"].to_i.positive? ? data["duration_mins"] : @duration_mins,
      difficulty:    Workout::DIFFICULTIES.include?(data["difficulty"]) ? data["difficulty"] : @difficulty,
      status:        "preview",
      structure:     data["structure"]
    )

    workout.tags = tags
    workout
  end
end
