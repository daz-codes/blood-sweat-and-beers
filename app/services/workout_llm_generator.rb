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
                  format:             { type: "string", enum: %w[straight amrap rounds emom tabata ladder mountain] },
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

  def self.call(user:, duration_mins:, difficulty:, tag_ids: [], source_workout: nil)
    new(user: user, tag_ids: tag_ids, duration_mins: duration_mins, difficulty: difficulty, source_workout: source_workout).call
  end

  def initialize(user:, duration_mins:, difficulty:, tag_ids: [], source_workout: nil)
    @user           = user
    @tag_ids        = Array(tag_ids).map(&:to_i).reject(&:zero?)
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
      tag_names        = Tag.where(id: @tag_ids).order(:name).pluck(:name)
      prompt           = build_prompt(tag_names, context_workouts)
      workout_data     = call_llm(prompt)
      create_workout(workout_data, tag_names)
    end
  end

  private

  def fetch_context
    ids = @tag_ids.any? ? Workout.most_liked_with_tags(@tag_ids, limit: 25).pluck(:id) : []
    if ids.size < 5
      ids = Workout.left_joins(:workout_likes)
                   .group(:id)
                   .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
                   .limit(25)
                   .pluck(:id)
    end
    return [] if ids.empty?
    Workout.where(id: ids).includes(:tags)
  end

  def build_prompt(tag_names, context_workouts)
    tag_str = tag_names.any? ? tag_names.join(", ") : "general fitness"
    context_json = context_workouts.map do |w|
      { name: w.name, tags: w.tags.map(&:name), duration_mins: w.duration_mins,
        difficulty: w.difficulty, structure: w.structure }
    end.to_json

    sections = []

    sections << <<~BASE
      You are a personal trainer specialising in functional fitness (Hyrox, Deka, obstacle racing).

      Generate a #{@duration_mins}-minute #{@difficulty} workout for someone training in: #{tag_str}.
    BASE

    user_context = build_user_context
    sections << user_context if user_context.present?

    sport_context = load_sport_context(tag_names)
    sections << sport_context if sport_context.present?

    sections << <<~COMMUNITY
      Here are #{context_workouts.size} popular community workouts for inspiration (use their structure and exercise choices as a guide):
      #{context_json}
    COMMUNITY

    sections << <<~RULES
      Use the create_workout tool. Requirements:
      - Total duration close to #{@duration_mins} minutes
      - Sections format: warm-up, main set, and optional finisher
      - Be specific with reps, distances, and weights
      - workout_type should always be "custom"
      - Give it a punchy, memorable name — something a gym community would actually call it, not a generic description
      - You may use ladder or mountain sections for variety, but ONLY when all exercises share the same metric AND the step size is realistic:
        * reps ladder: step 1–5. E.g. start:10 end:1 step:1 = 10,9,8...1 reps. Or start:15 end:5 step:5 = 15,10,5 reps.
        * calories ladder: step 5–10 (never less than 5). E.g. start:20 end:5 step:5 = 20,15,10,5 cal. Or start:30 end:10 step:10 = 30,20,10 cal.
        * distance_m ladder: step 10–20 (never less than 10). E.g. start:40 end:20 step:10 = 40m,30m,20m. Or start:60 end:20 step:20 = 60m,40m,20m.
        * kg ladder: step 5–10. E.g. start:60 end:40 step:10 = 60,50,40 kg.
        * mountain: same rules, ascend then descend. E.g. start:5 peak:15 end:5 step:5 varies:"reps" = 5,10,15,10,5 reps.
        * INVALID: mixing reps-based, distance-based, and calorie-based exercises in the same ladder. Use rounds or straight instead.
    RULES

    sections.join("\n")
  end

  def build_remix_prompt
    source_json = {
      tags:          @source_workout.tags.map(&:name),
      duration_mins: @source_workout.duration_mins,
      difficulty:    @source_workout.difficulty,
      structure:     @source_workout.structure
    }.to_json

    <<~PROMPT.strip
      You are a personal trainer specialising in functional fitness (Hyrox, Deka, obstacle racing).

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

  # Builds a concise user profile block to inject into the prompt.
  def build_user_context
    parts = []

    physical = []
    physical << "Age: #{@user.age}" if @user.age.present?
    physical << "Height: #{@user.height_cm}cm" if @user.height_cm.present?
    physical << "Weight: #{@user.weight_kg.to_f.round(1)}kg" if @user.weight_kg.present?
    parts << "Athlete profile: #{physical.join(", ")}" if physical.any?

    if @user.pool_length.present?
      parts << "Pool length: #{@user.pool_length}"
    end

    if @user.run_preference.present?
      run_pref = @user.run_preference.capitalize
      parts << "Run environment: #{run_pref}#{" — always use 1% treadmill incline for outdoor equivalence" if @user.run_preference == "treadmill"}"
    end

    if @user.equipment.present?
      parts << "Available equipment: #{@user.equipment.join(", ")}"
    end

    pbs = format_personal_bests
    parts << pbs if pbs.present?

    return nil if parts.empty?

    <<~CTX
      ## Athlete Context
      #{parts.map { |p| "- #{p}" }.join("\n")}
      Use this information to calibrate weights, distances, and pacing appropriately.
    CTX
  end

  # Formats personal bests as human-readable strings for the prompt.
  def format_personal_bests
    return nil if @user.personal_bests.blank?

    pbs = @user.personal_bests
    lines = []

    time_labels = {
      "run_1mile" => "1 mile run", "run_1_5mile" => "1.5 mile run (Cooper)", "run_5km" => "5km run", "run_10km" => "10km run",
      "run_half_marathon" => "Half marathon",
      "swim_100m_fc" => "100m freestyle", "swim_400m" => "400m swim",
      "swim_1500m" => "1500m swim", "swim_1mile" => "1 mile swim",
      "row_500m" => "500m row", "row_1000m" => "1000m row", "row_2000m" => "2000m row",
      "ski_500m" => "500m ski erg", "ski_2000m" => "2000m ski erg",
      "assault_bike_50cal" => "Assault bike 50cal", "assault_bike_100cal" => "Assault bike 100cal",
      "floor_to_ceiling_30" => "30x floor-to-ceiling", "thrusters_50" => "50x thrusters",
      "wall_balls_100" => "100x wall balls", "hyrox_race" => "Hyrox race",
      "deka_fit" => "Deka Fit"
    }

    weight_labels = {
      "bench_1rm" => "Bench press 1RM", "squat_1rm" => "Squat 1RM",
      "deadlift_1rm" => "Deadlift 1RM", "clean_jerk_1rm" => "Clean & Jerk 1RM",
      "snatch_1rm" => "Snatch 1RM"
    }

    count_labels = {
      "press_ups_2min" => "Press-ups in 2 min", "pull_ups_max" => "Max pull-ups",
      "burpees_1min" => "Burpees in 1 min"
    }

    time_labels.each do |key, label|
      next unless pbs[key]
      secs = pbs[key].to_i
      h, rem = secs.divmod(3600)
      m, s = rem.divmod(60)
      formatted = h > 0 ? "#{h}:#{m.to_s.rjust(2, "0")}:#{s.to_s.rjust(2, "0")}" : "#{m}:#{s.to_s.rjust(2, "0")}"
      lines << "#{label}: #{formatted}"
    end

    weight_labels.each do |key, label|
      next unless pbs[key]
      lines << "#{label}: #{pbs[key].to_f.round(1)}kg"
    end

    count_labels.each do |key, label|
      next unless pbs[key]
      lines << "#{label}: #{pbs[key].to_i}"
    end

    return nil if lines.empty?

    "Personal bests:\n#{lines.map { |l| "  - #{l}" }.join("\n")}"
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
    tags = tag_names.map { |name| Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name } }

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
