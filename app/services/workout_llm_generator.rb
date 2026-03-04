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

  # Station/zone pools used to pre-select a subset before generation, so the LLM
  # is told exactly which movements to use rather than choosing from the full list.
  DEKA_ZONES = [
    "RAM Reverse Lunges", "Row", "Box Jump / Step Over", "Med Ball Sit-up Throw",
    "SkiErg", "Farmer's Carry", "Air Bike", "Dead Ball Yoke Over",
    "Sled Push / Pull", "RAM Weighted Burpees"
  ].freeze

  EVENT_STATIONS = {
    "hyrox"      => %w[SkiErg] + ["Sled Push", "Sled Pull", "Burpee Broad Jumps",
                                   "Rowing", "Farmers Carry", "Sandbag Lunges", "Wall Balls"],
    "deka"       => DEKA_ZONES,
    "deka-fit"   => DEKA_ZONES,
    "deka-strong" => DEKA_ZONES,
    "deka-mile"  => DEKA_ZONES,
    "deka-atlas" => [
      "Barbell Thrusters", "Bar-Facing Burpees Over Bar", "Surrender Lunges (weighted)",
      "Single Arm DB Ground to Overhead (alternating)", "Dumbbell Bear Crawl",
      "Weighted Sit-ups", "Farmer's Carry", "DB Shoulder to Overhead Press",
      "Jump Rope Single Unders", "Atlas Shoulder to Carry"
    ],
  }.freeze

  # Weighted count distribution: heavily favour 2-4, allow 1 and 5-6 occasionally.
  STATION_COUNT_WEIGHTS = [1, 2, 2, 3, 3, 3, 4, 4, 5, 6].freeze

  # Race-accurate reference data for each station/zone — weights and distances.
  # Injected for the selected stations only so the LLM calibrates correctly
  # without being tempted to include every station it sees in a table.
  HYROX_REFERENCE = {
    "SkiErg"             => "1000m",
    "Sled Push"          => "50m | Open: 152kg (M) / 102kg (F) | Pro: 202kg (M) / 152kg (F)",
    "Sled Pull"          => "50m | Open: 103kg (M) / 78kg (F) | Pro: 153kg (M) / 103kg (F)",
    "Burpee Broad Jumps" => "80m",
    "Rowing"             => "1000m",
    "Farmers Carry"      => "200m | Open: 2×24kg (M) / 2×16kg (F) | Pro: 2×32kg (M) / 2×24kg (F)",
    "Sandbag Lunges"     => "100m | Open: 20kg (M) / 10kg (F) | Pro: 30kg (M) / 20kg (F)",
    "Wall Balls"         => "100 reps | Open: 6kg to 10ft (M) / 4kg to 9ft (F) | Pro: 9kg to 10ft (M) / 6kg to 9ft (F)",
  }.freeze

  DEKA_REFERENCE = {
    "RAM Reverse Lunges"   => "30 reps (15/leg) | 25kg (M) / 15kg (F)",
    "Row"                  => "500m",
    "Box Jump / Step Over" => "20 reps | 24\" box",
    "Med Ball Sit-up Throw" => "25 reps | 9kg (M) / 6.5kg (F)",
    "SkiErg"               => "500m",
    "Farmer's Carry"       => "100m | 27kg each hand (M) / 18kg each hand (F)",
    "Air Bike"             => "25 calories",
    "Dead Ball Yoke Over"  => "20 reps (10/side) | 27kg (M) / 18kg (F)",
    "Sled Push / Pull"     => "100m (push 10m + pull 10m × 5)",
    "RAM Weighted Burpees" => "20 reps | 20kg (M) / 10kg (F)",
  }.freeze

  DEKA_ATLAS_REFERENCE = {
    "Barbell Thrusters"                              => "20 reps | 45kg (M) / 30kg (F)",
    "Bar-Facing Burpees Over Bar"                    => "20 reps",
    "Surrender Lunges (weighted)"                    => "20 reps | 22.5kg (M) / 15kg (F)",
    "Single Arm DB Ground to Overhead (alternating)" => "20 reps | 22.5kg (M) / 15kg (F)",
    "Dumbbell Bear Crawl"                            => "40m | 22.5kg (M) / 15kg (F)",
    "Weighted Sit-ups"                               => "20 reps | 15kg (M) / 9kg (F)",
    "Farmer's Carry"                                 => "60m | 45kg each hand (M) / 32kg each hand (F)",
    "DB Shoulder to Overhead Press"                  => "20 reps | 22.5kg (M) / 15kg (F)",
    "Jump Rope Single Unders"                        => "100 reps",
    "Atlas Shoulder to Carry"                        => "100m | 45kg (M) / 32kg (F)",
  }.freeze

  EVENT_REFERENCE = {
    "hyrox"       => HYROX_REFERENCE,
    "deka"        => DEKA_REFERENCE,
    "deka-fit"    => DEKA_REFERENCE,
    "deka-strong" => DEKA_REFERENCE,
    "deka-mile"   => DEKA_REFERENCE,
    "deka-atlas"  => DEKA_ATLAS_REFERENCE,
  }.freeze

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
                        distance_m:  { type: "integer", description: "Distance in metres for ONE execution of this exercise row. For 'rounds' sections this is the PER-ROUND distance — the system multiplies by the rounds count automatically, so NEVER pre-multiply. E.g. in a 3-round section '3×100m Freestyle per round' → distance_m: 100 (not 300). For non-rounds sections (straight, for_time, amrap) this is the full total: '4×100m Freestyle' → distance_m: 400. For swimming: only use 25, 50, or multiples of 100 — never 75, 125, 150, 175 etc." },
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

  def self.call(user:, duration_mins:, difficulty:, main_tag_id: nil, minor_tag_ids: [], group_code_id: nil, target_distance_km: nil, tag_ids: [], source_workout: nil)
    new(user: user, main_tag_id: main_tag_id, minor_tag_ids: minor_tag_ids, group_code_id: group_code_id, target_distance_km: target_distance_km, tag_ids: tag_ids, duration_mins: duration_mins, difficulty: difficulty, source_workout: source_workout).call
  end

  def initialize(user:, duration_mins:, difficulty:, main_tag_id: nil, minor_tag_ids: [], group_code_id: nil, target_distance_km: nil, tag_ids: [], source_workout: nil)
    @user               = user
    @main_tag           = main_tag_id.present? ? Tag.find_by(id: main_tag_id) : nil
    @minor_tags         = Tag.where(id: Array(minor_tag_ids).map(&:to_i).reject(&:zero?))
    @group_code_tag     = group_code_id.present? ? Tag.find_by(id: group_code_id) : nil
    @target_distance_km = target_distance_km.to_f > 0 ? target_distance_km.to_f : nil
    # tag_ids kept for backwards compat (remix path uses source workout tags directly)
    @tag_ids            = tag_ids.any? ? Array(tag_ids).map(&:to_i).reject(&:zero?) : ([@main_tag&.id] + @minor_tags.map(&:id)).compact
    @duration_mins      = duration_mins.to_i
    @difficulty         = difficulty
    @source_workout     = source_workout
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
      workout_data     = collapse_duplicate_exercises(workout_data)
      workout_data     = snap_swim_distances(workout_data) if is_swim_session?
      if @target_distance_km
        workout_data = call_distance_correction(workout_data)  # LLM correction pass
        workout_data = snap_swim_distances(workout_data) if is_swim_session?  # re-snap after LLM correction
        workout_data = adjust_to_target_distance(workout_data)  # silent safety net
      end
      all_tag_names    = ([@main_tag&.name] + @minor_tags.map(&:name) + [@group_code_tag&.name]).compact
      create_workout(workout_data, all_tag_names)
    end
  end

  private

  def fetch_context
    # Event sessions (Hyrox, Deka) skip community workouts — they all look the same
    # and act as a strong template that prevents variety.
    return [] if event_session?

    # Group code takes full priority — draw from a pool and sample randomly for variety.
    if @group_code_tag
      ids = Workout.most_liked_with_tags([@group_code_tag.id], limit: 20).pluck(:id)
      return [] if ids.empty?
      return Workout.where(id: ids.sample(3)).includes(:tags)
    end

    # Fetch a broader pool of popular workouts by tag, then sample randomly so
    # the LLM gets different inspiration each generation (prevents template lock-in).
    ids = @main_tag ? Workout.most_liked_with_tags([@main_tag.id], limit: 20).pluck(:id) : []

    # Supplement with minor-focus matches (meta-only minor tags like no-run don't help here)
    focus_minor_ids = @minor_tags.reject { |t| t.slug.in?(META_MINOR_SLUGS) }.map(&:id)
    if ids.size < 10 && focus_minor_ids.any?
      minor_ids = Workout.most_liked_with_tags(focus_minor_ids, limit: 20)
                         .where.not(id: ids.any? ? ids : nil)
                         .pluck(:id)
      ids += minor_ids
    end

    # Still thin? Fall back to globally popular workouts
    if ids.size < 3
      ids = Workout.left_joins(:workout_likes)
                   .group(:id)
                   .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
                   .limit(20)
                   .pluck(:id)
    end

    return [] if ids.empty?
    Workout.where(id: ids.sample(3)).includes(:tags)
  end

  # Detects sections where every exercise entry is identical (same name + metrics)
  # and collapses them into a rounds section with a single entry.
  # E.g. 5 × { name: "Freestyle", distance_m: 25 } → rounds: 5, exercises: [{ name: "Freestyle", distance_m: 25 }]
  def collapse_duplicate_exercises(workout_data)
    Array(workout_data.dig("structure", "sections")).each do |section|
      exercises = Array(section["exercises"])
      next if exercises.size < 2

      # Fingerprint each exercise ignoring notes (notes often differ slightly)
      fingerprint = ->(e) { e.slice("name", "reps", "distance_m", "calories", "duration_s", "weight_kg") }

      first_fp = fingerprint.call(exercises.first)
      next unless exercises.all? { |e| fingerprint.call(e) == first_fp }

      # All identical — collapse into rounds
      count = exercises.size
      existing_rounds = section["rounds"].to_i
      new_rounds = existing_rounds > 1 ? existing_rounds * count : count

      section["rounds"]    = new_rounds
      section["format"]    = "rounds" if section["format"] == "straight"
      section["exercises"] = [ exercises.first ]
    end

    workout_data
  end

  # Second LLM pass: shows the model the actual total it produced vs the target and
  # asks it to fix the discrepancy. Skipped when already exact or within one pool length.
  def call_distance_correction(workout_data)
    target_m = (@target_distance_km * 1000).to_i
    pool_len = [(@user.pool_length.presence || "25m").to_i, 25].max

    sections = workout_data.dig("structure", "sections").to_a
    actual_m = sections.sum do |s|
      [s["rounds"].to_i, 1].max * Array(s["exercises"]).sum { |e| e["distance_m"].to_i }
    end

    diff_m = target_m - actual_m
    return workout_data if diff_m.abs < pool_len  # already exact enough

    direction = diff_m > 0 ? "#{diff_m}m short" : "#{diff_m.abs}m over"

    prompt = <<~PROMPT
      A swimming workout was generated targeting #{@target_distance_km}km (#{target_m}m) total.
      After summing all exercises (accounting for rounds × per-round distances) the actual total is #{actual_m}m — #{direction}.

      Current workout JSON:
      #{workout_data.to_json}

      Please use the create_workout tool to return a corrected version that totals EXACTLY #{target_m}m.

      Rules:
      - Adjust one or more exercise distances — extend or add a rep block in the most natural place
      - Every distance_m must be a whole multiple of #{pool_len}m AND must be 25, 50, or a multiple of 100 (valid: 25, 50, 100, 200, 300, 400… NEVER 75, 125, 150, 175, 225, 250 etc.)
      - Cool-down section: never exceed 200m total. Use the cool-down as the primary adjustment target when the diff is small
      - For 'rounds' sections: distance_m is per-round (system multiplies by rounds). Total for a section = sum(distance_m) × rounds
      - CRITICAL: when you change a distance_m you MUST also update the exercise name and notes to match. E.g. if "8 × 100m" (distance_m:800) becomes 1000m, update to "10 × 100m" in name/notes. Never leave the name/notes describing a different rep count than distance_m.
      - Verify the sum before returning: list each section's contribution and confirm they total #{target_m}m
      - Do not change the workout name, goal, session structure, or format types
    PROMPT

    call_llm(prompt)
  rescue StandardError
    workout_data  # if the correction call fails, return the original
  end

  # Post-processes the LLM output to guarantee the total distance matches the target.
  # Steps:
  #   1. Round every distance_m to the nearest pool-length multiple (fixes fractional distances)
  #   2. Re-sum the actual total
  #   3. Apply the diff to the best candidate exercise (prefer main sections, straight > rounds)
  #   4. If no single exercise can absorb it cleanly, add an Easy Freestyle entry to the cool-down
  def adjust_to_target_distance(workout_data)
    target_m = (@target_distance_km * 1000).to_i
    pool_len  = [(@user.pool_length.presence || "25m").to_i, 25].max
    swim      = is_swim_session?

    sections = workout_data.dig("structure", "sections").to_a

    # ── Step 1: Snap all distances to valid values ───────────────────────────
    # Swim: 25, 50, or multiples of 100. Others: nearest pool-length multiple.
    sections.each do |section|
      Array(section["exercises"]).each do |ex|
        next unless ex["distance_m"].to_i > 0
        ex["distance_m"] = if swim
          snap_swim_distance(ex["distance_m"].to_i)
        else
          [((ex["distance_m"].to_f / pool_len).round * pool_len).to_i, pool_len].max
        end
      end
    end

    # ── Step 1b: Cap cool-down at 200m (swim sessions) ───────────────────────
    if swim
      cd = sections.find { |s| s["name"].to_s.downcase.match?(/cool|down/) }
      if cd
        cd_exs   = Array(cd["exercises"]).select { |e| e["distance_m"].to_i > 0 }
        cd_total = cd_exs.sum { |e| e["distance_m"].to_i }
        if cd_total > 200
          ex = cd_exs.max_by { |e| e["distance_m"].to_i }
          ex["distance_m"] = snap_swim_distance([ex["distance_m"].to_i - (cd_total - 200), 25].max)
        end
      end
    end

    # ── Step 2: Actual total after snapping ──────────────────────────────────
    actual_m = sections.sum do |s|
      [s["rounds"].to_i, 1].max * Array(s["exercises"]).sum { |e| e["distance_m"].to_i }
    end

    diff_m = target_m - actual_m
    return workout_data if diff_m.zero?

    # ── Step 3: Find best section/exercise to absorb the diff ────────────────
    rep_scheme = ->(e) { (e["notes"].to_s + e["name"].to_s).match?(/\d+\s*[×x×]/) }

    # Direction-aware sort:
    #   Under target (diff > 0): add to cool-down first (it's the intended buffer)
    #   Over target  (diff < 0): try main sections first — cool-down is small and
    #     warm/cool sections rarely have enough distance to absorb a large reduction
    sorted_sections = sections.sort_by do |s|
      name = s["name"].to_s.downcase
      is_cd   = name.match?(/cool|down/)
      is_warm = name.include?("warm")
      if diff_m > 0
        is_cd ? 0 : (is_warm ? 1 : 2)   # cool-down first when adding
      else
        (is_cd || is_warm) ? 2 : 0       # main sections first when removing
      end
    end

    applied = false
    sorted_sections.each do |section|
      break if applied
      is_cooldown = section["name"].to_s.downcase.match?(/cool|down/)
      rounds = [section["rounds"].to_i, 1].max

      # Under target: skip exercises with embedded rep counts (notes would become inconsistent).
      # Over target:  allow rep-scheme exercises — swim main sets are almost always named
      #               "4 × 200m Freestyle" so filtering them out leaves nothing to reduce.
      dist_exs = Array(section["exercises"])
                   .select { |e| e["distance_m"].to_i > 0 }
                   .reject { |e| !is_cooldown && diff_m > 0 && rep_scheme.call(e) }
      next if dist_exs.empty?
      next unless (diff_m % rounds).zero?

      per_round = diff_m / rounds

      ex = dist_exs.max_by { |e| e["distance_m"].to_i }

      if is_cooldown && swim
        # Cool-down buffer: allow 25m granularity, hard cap at 200m total
        next unless (per_round % pool_len).zero?
        cd_total  = dist_exs.sum { |e| e["distance_m"].to_i }
        new_dist  = ex["distance_m"].to_i + per_round
        new_total = cd_total - ex["distance_m"].to_i + new_dist
        next if new_dist <= 0 || new_total > 200 || new_total < pool_len
        ex["distance_m"] = new_dist
        applied = true
      elsif swim
        # Main set: result must snap to a valid swim distance
        next unless (per_round % pool_len).zero?
        raw      = ex["distance_m"].to_i + per_round
        new_dist = snap_swim_distance(raw)
        next if new_dist <= 0
        # For positive diffs: only apply if result is already valid (no notes drift)
        # For negative diffs: apply even if snap adjusts by one step (closer > nothing)
        next if diff_m > 0 && new_dist != raw
        ex["distance_m"] = new_dist
        applied = true
      else
        next unless (per_round % pool_len).zero?
        new_dist = ex["distance_m"].to_i + per_round
        next if new_dist <= 0
        ex["distance_m"] = new_dist
        applied = true
      end
    end

    # If step 3 adjusted but snap left a residual diff, recalculate so step 4 can also run
    if applied
      actual_m = sections.sum { |s| [s["rounds"].to_i, 1].max * Array(s["exercises"]).sum { |e| e["distance_m"].to_i } }
      diff_m   = target_m - actual_m
      applied  = diff_m.zero?
    end

    # ── Step 4: Fallback — add/remove from cool-down (capped at 200m) ────────
    unless applied
      cooldown = sections.find { |s| s["name"].to_s.downcase.match?(/cool/) }
      unless cooldown
        cooldown = { "name" => "Cool-down", "format" => "straight", "exercises" => [] }
        sections << cooldown
        workout_data["structure"]["sections"] = sections
      end

      cd_exs   = Array(cooldown["exercises"]).select { |e| e["distance_m"].to_i > 0 }
      cd_total = cd_exs.sum { |e| e["distance_m"].to_i }
      gran     = pool_len  # 25m for swim (pool_len == 25), or pool_len for others

      if diff_m > 0
        # Add up to 200m cap
        add = [diff_m, 200 - cd_total].min
        add = (add / gran).to_i * gran  # snap to granularity
        if add > 0
          if cd_exs.any?
            ex = cd_exs.max_by { |e| e["distance_m"].to_i }
            ex["distance_m"] += add
          else
            cooldown["exercises"] ||= []
            cooldown["exercises"] << { "name" => "Easy Freestyle", "distance_m" => add, "notes" => "easy" }
          end
        end
      elsif diff_m < 0 && cd_exs.any?
        # Trim cool-down to fix overshoot
        ex       = cd_exs.max_by { |e| e["distance_m"].to_i }
        reduce   = (diff_m.abs / gran).to_i * gran
        new_dist = [ex["distance_m"].to_i - reduce, gran].max
        ex["distance_m"] = new_dist
      end
    end

    # ── Update duration_mins proportionally ─────────────────────────────────
    if actual_m > 0 && workout_data["duration_mins"].to_i > 0
      workout_data["duration_mins"] = ((target_m.to_f / actual_m) * workout_data["duration_mins"]).round
    end

    workout_data
  end

  def build_prompt(context_workouts)
    main_name  = @main_tag&.name || "general fitness"
    minor_str  = @minor_tags.map(&:name).join(", ")

    dist_str = @target_distance_km ? "#{@target_distance_km.to_s.delete_suffix(".0")}km" : nil

    selected_stations = pick_event_stations
    station_constraint = if selected_stations
      n = selected_stations.size
      " Build the entire session around these #{n} station#{"s" if n > 1} ONLY — #{selected_stations.join(", ")}. Do not include any other #{main_name} stations."
    end

    task_sentence = if dist_str && minor_str.present?
      "Generate a #{@difficulty} #{main_name} session covering #{dist_str} with a focus on: #{minor_str}.#{station_constraint}"
    elsif dist_str
      "Generate a #{@difficulty} #{main_name} session covering #{dist_str}.#{station_constraint}"
    elsif minor_str.present?
      "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} session with a focus on: #{minor_str}.#{station_constraint}"
    else
      "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} session.#{station_constraint}"
    end

    sections = []

    sections << <<~BASE
      You are a personal trainer specialising in writing fun and exciting workouts that improve people's overall fitness.

      #{task_sentence}
    BASE

    if selected_stations
      # For event sessions with a station selection: inject the training philosophy
      # from the context file but NOT the station table (which causes the LLM to
      # treat it as a checklist). Station reference is injected separately below.
      sport_context = load_sport_context([@main_tag&.name].compact)
      if sport_context.present?
        # Strip the station table (the block between "## The N Stations" and "## Training")
        philosophy_only = sport_context.gsub(/##\s+The \d+ (?:Stations|Zones).*?(?=##\s+Training)/m, "")
        sections << philosophy_only if philosophy_only.strip.present?
      end
      station_ref = build_station_reference(selected_stations)
      sections << station_ref if station_ref
    else
      sport_context = load_sport_context([@main_tag&.name].compact)
      sections << sport_context if sport_context.present?
    end

    if context_workouts.any?
      context_json = context_workouts.map do |w|
        { name: w.name, tags: w.tags.map(&:name), duration_mins: w.duration_mins,
          difficulty: w.difficulty, structure: w.structure }
      end.to_json
      sections << <<~COMMUNITY
        Here are #{context_workouts.size} popular community workouts for FORMAT INSPIRATION ONLY — do not copy their station/exercise selection:
        #{context_json}
      COMMUNITY
    end

    # Athlete context goes last before rules — closest to generation, hardest to ignore.
    user_context = build_user_context
    sections << user_context if user_context.present?

    sport_rule  = sport_purity_rule
    pace_limits = pace_limit_rule
    station_rule = if selected_stations
      n = selected_stations.size
      "- HARD RULE — STATION CONSTRAINT: Use ONLY #{n} station#{"s" if n > 1} in this session: #{selected_stations.join(", ")}. Every exercise in every main section MUST be one of these. No other #{main_name} stations permitted."
    end

    duration_rule = if @target_distance_km
      target_m = (@target_distance_km * 1000).to_i
      "- TARGET DISTANCE: #{dist_str} (#{target_m}m) total. This overrides any volume budget table in the sport guidelines.\n" \
      "- DISTANCE ACCOUNTING — the system calculates section totals as follows:\n" \
      "    * rounds sections: section_total = sum(distance_m per exercise) × rounds\n" \
      "    * all other sections: section_total = sum(distance_m per exercise)\n" \
      "- Therefore distance_m in a rounds section must be the PER-ROUND value. NEVER pre-multiply by rounds.\n" \
      "- Plan before writing: list each section, its format, rounds, and distance. E.g.:\n" \
      "    Warm-up (straight) 500m + Main Set (rounds×3, 600m/round = 1800m) + Cool-down (straight) 200m = 2500m\n" \
      "- The planned totals must sum exactly to #{target_m}m before you fill in the tool.\n" \
      "- Set duration_mins to a realistic time to cover #{dist_str} at #{@difficulty} pace."
    else
      "- Total duration close to #{@duration_mins} minutes"
    end

    sections << <<~RULES
      Use the create_workout tool. Requirements:
      #{duration_rule}
      #{station_rule}
      - Sections: warm-up, main set (can be split into multiple sections), optional finisher, cool-down
      - Warm-up: easy cardio + a few bodyweight movements to loosen up — keep it brief
      - Finisher: something punchy and challenging to end on
      - Cool-down: ALWAYS end with a 5-minute cool-down section (format: straight, duration_mins: 5) containing 3–5 static stretches (e.g. hip flexor stretch, hamstring stretch, chest opener, thoracic rotation). No reps or distances — use notes on each exercise to describe the stretch (e.g. "30s each side").
      - Be specific with reps, distances, and weights
      - Give it a punchy, memorable name — something a gym community would actually call it (CrossFit-style), not a generic description
      #{sport_rule}
      #{pace_limits}
      - FORMAT SELECTION — choose the best format for each section. Actively vary formats across sections (do not use the same format for every section):
        * tabata — high-intensity cardio bursts or bodyweight finishers. 20s on / 10s off × 8 rounds = exactly 4 minutes. Set duration_mins: 4. Great for: assault bike, ski erg, burpees, KB swings, box jumps, jump rope. Do NOT add reps or calories to tabata exercises — the 20s interval is the constraint. You may specify distance_m or weight_kg where relevant.
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
      - NEVER list the same exercise more than once in a section's exercises array. If you need the same movement repeated (e.g. 5 × 25m Freestyle), use rounds: 5 with a single exercise entry — not 5 separate entries. Duplicate entries are always wrong.
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
      "- This is a swimming session — use ONLY swimming strokes, drills, and kick/pull sets. Do NOT add gym exercises.\n" \
      "- SWIM DISTANCE RULE: every distance_m MUST be 25, 50, or a multiple of 100. " \
      "Valid: 25, 50, 100, 200, 300, 400, 500, 800, 1000, 1500. " \
      "NEVER use 75, 125, 150, 175, 225, 250 or any other value — these are not natural pool distances.\n" \
      "- Cool-down: 100m standard. Never more than 200m."
    else
      "- Always end with a 5-minute cool-down section (format: straight, duration_mins: 5) of 3–5 static stretches. No reps or distances — use notes to describe hold time (e.g. \"30s each side\")."
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

  # Returns true when the main tag is an event type with a fixed station/zone list.
  def event_session?
    EVENT_STATIONS.key?(@main_tag&.slug || "")
  end

  # Builds a compact reference block listing only the selected stations with their
  # race-accurate weights/distances. Replaces the full station table from the context
  # file so the LLM can't use the table as a checklist of "things to include".
  def build_station_reference(stations)
    ref_map = EVENT_REFERENCE[@main_tag&.slug || ""] || {}
    lines = stations.filter_map { |s| ref_map[s] ? "  #{s}: #{ref_map[s]}" : nil }
    return nil if lines.empty?
    "Race-accurate reference for this session's stations (weights / distances):\n#{lines.join("\n")}"
  end

  # Meta-instruction minor tags that restrict the session but are NOT focus movements.
  # These must NOT disable station selection (they're constraints, not content choices).
  META_MINOR_SLUGS = %w[no-run no-running no-runs].freeze

  # Randomly selects a subset of event stations for this session.
  # Returns nil if the event has no station pool, or if the user specified actual
  # focus movements as minor tags (in which case the LLM uses those freely).
  # Meta-instruction tags (no-run etc.) are ignored for this check.
  def pick_event_stations
    main_slug = @main_tag&.slug || ""
    pool = EVENT_STATIONS[main_slug]
    return nil if pool.nil?

    focus_tags = @minor_tags.reject { |t| t.slug.in?(META_MINOR_SLUGS) }
    return nil if focus_tags.any?  # user specified actual movements — let them guide it

    count = STATION_COUNT_WEIGHTS.sample
    pool.shuffle.first(count)
  end

  def is_swim_session?
    slug = @main_tag&.slug || ""
    slug.in?(%w[swimming swim]) || @minor_tags.any? { |t| t.slug.match?(/swim/) }
  end

  # Snaps a distance to the valid set for swimming: 25, 50, or nearest multiple of 100.
  # E.g. 75 → 50, 125 → 100, 150 → 200, 175 → 200.
  def snap_swim_distance(m)
    return 0 if m <= 0
    return 25 if m < 38
    return 50 if m < 76
    ((m.to_f / 100).round * 100).clamp(100, 10_000)
  end

  # Post-processing pass for swim sessions: snaps all exercise distances to the valid set
  # (25, 50, or multiples of 100) and caps the cool-down at 200m.
  def snap_swim_distances(workout_data)
    sections = Array(workout_data.dig("structure", "sections"))
    sections.each do |section|
      is_cooldown = section["name"].to_s.downcase.match?(/cool|down/)
      Array(section["exercises"]).each do |ex|
        next unless ex["distance_m"].to_i > 0
        ex["distance_m"] = snap_swim_distance(ex["distance_m"].to_i)
      end
      next unless is_cooldown
      cd_exs   = Array(section["exercises"]).select { |e| e["distance_m"].to_i > 0 }
      cd_total = cd_exs.sum { |e| e["distance_m"].to_i }
      if cd_total > 200
        # Reduce the largest exercise to bring the total back to ≤ 200m
        ex = cd_exs.max_by { |e| e["distance_m"].to_i }
        trimmed = [ex["distance_m"].to_i - (cd_total - 200), 25].max
        ex["distance_m"] = snap_swim_distance(trimmed)
      end
    end
    workout_data
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
      # Preserve tag_type for group codes — don't downgrade an existing group_code tag to minor
      Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name }
    end
    # Ensure the group code tag's type is never overwritten by the LLM name-matching path
    if @group_code_tag && (existing = tags.find { |t| t.id == @group_code_tag.id })
      existing.update!(tag_type: "group_code") unless existing.group_code?
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
