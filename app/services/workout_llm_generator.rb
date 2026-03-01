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
                  varies:             { type: "string", enum: %w[reps calories kg distance_m], description: "What changes each rung (ladder/mountain sections only)" },
                  start:              { type: "number", description: "Starting value for ladder/mountain" },
                  end:                { type: "number", description: "Ending value for ladder/mountain" },
                  peak:               { type: "number", description: "Peak value for mountain sections" },
                  step:               { type: "number", description: "Increment between rungs, defaults to 1" },
                  rest_between_rungs: { type: "integer", description: "Rest in seconds between each rung (optional)" },
                  exercises: {
                    type: "array",
                    items: {
                      type: "object",
                      required: ["name"],
                      properties: {
                        name:        { type: "string" },
                        reps:        { type: "integer" },
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

    <<~PROMPT.strip
      You are a personal trainer specialising in functional fitness (Hyrox, Deka, obstacle racing).

      Generate a #{@duration_mins}-minute #{@difficulty} workout for someone training in: #{tag_str}.

      Here are #{context_workouts.size} popular community workouts for inspiration (use their structure and exercise choices as a guide):
      #{context_json}

      Use the create_workout tool. Requirements:
      - Total duration close to #{@duration_mins} minutes
      - Sections format: warm-up, main set, and optional finisher
      - Be specific with reps, distances, and weights
      - workout_type should always be "custom"
      - Give it a punchy, memorable name — something a gym community would actually call it, not a generic description
      - You may use ladder or mountain sections for variety:
        * ladder: a sequence of values (reps, calories, kg) ascending or descending. E.g. start:10 end:1 step:1 varies:"reps" = 10,9,8...1 reps each rung. Or start:50 end:10 step:10 varies:"calories" = 50,40,30,20,10 cal.
        * mountain: ascend to a peak then descend. E.g. start:1 peak:5 end:1 step:1 varies:"reps" = 1,2,3,4,5,4,3,2,1 reps. Exercises listed are performed every rung.
    PROMPT
  end

  def build_remix_prompt
    source_json = {
      name:          @source_workout.name,
      tags:          @source_workout.tags.map(&:name),
      duration_mins: @source_workout.duration_mins,
      difficulty:    @source_workout.difficulty,
      structure:     @source_workout.structure
    }.to_json

    <<~PROMPT.strip
      You are a personal trainer specialising in functional fitness (Hyrox, Deka, obstacle racing).

      Generate a #{@duration_mins}-minute #{@difficulty} workout inspired by this existing workout:
      #{source_json}

      Use its exercise types, movement patterns, and overall style as inspiration — but create a fresh variation. Change the exercises, rep schemes, or section structure enough that it feels like a new session, not a copy.

      Use the create_workout tool. Requirements:
      - Total duration close to #{@duration_mins} minutes
      - Similar feel and focus to the source workout, but distinct enough to be worth doing separately
      - Be specific with reps, distances, and weights
      - workout_type should always be "custom"
      - Give it a punchy, memorable name — something a gym community would actually call it
      - You may use ladder or mountain sections for variety:
        * ladder: ascending or descending sequence. E.g. start:10 end:1 step:1 varies:"reps" = 10,9,8...1 reps each rung.
        * mountain: ascend to peak then descend. E.g. start:1 peak:5 end:1 step:1 varies:"reps" = 1,2,3,4,5,4,3,2,1.
    PROMPT
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
    raise WorkoutGenerationError, "API error #{response.code}: #{response.body}" unless response.code.to_i == 200

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
