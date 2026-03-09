require "net/http"
require "json"

# Replaces a single exercise in a workout's structure with an LLM-generated alternative.
# Finds a contextually appropriate swap — same muscle group, same format, similar intensity.
#
# Usage:
#   replacement = ExerciseSwapService.call(
#     workout:        @workout,
#     section_index:  0,
#     exercise_index: 2,
#     reason:         "no tyre available"   # optional
#   )
#   # Returns the replacement exercise hash, or raises on failure.
class ExerciseSwapService
  class SwapError < StandardError; end

  SWAP_TOOL = {
    name: "replace_exercise",
    description: "Return a single replacement exercise.",
    input_schema: {
      type: "object",
      required: [ "name" ],
      properties: {
        name:       { type: "string",  description: "Exercise name" },
        reps:       { type: "integer", description: "Rep count" },
        calories:   { type: "integer", description: "Calorie target" },
        distance_m: { type: "integer", description: "Distance in metres" },
        duration_s: { type: "integer", description: "Duration in seconds" },
        weight_kg:  { type: "number",  description: "Load in kg" },
        notes:      { type: "string",  description: "Coaching notes or cues" }
      }
    }
  }.freeze

  API_URI = URI("https://api.anthropic.com/v1/messages").freeze
  MODEL   = "claude-haiku-4-5-20251001".freeze

  def self.call(workout:, section_index:, exercise_index:, reason: nil)
    new(workout, section_index, exercise_index, reason).call
  end

  def initialize(workout, section_index, exercise_index, reason)
    @workout        = workout
    @section_index  = section_index
    @exercise_index = exercise_index
    @reason         = reason.presence
  end

  def call
    section  = sections[@section_index]  or raise SwapError, "Section not found"
    exercise = Array(section["exercises"])[@exercise_index] or raise SwapError, "Exercise not found"

    replacement = call_llm(section, exercise)

    # Update the persisted structure in place
    updated = @workout.structure.deep_dup
    updated["sections"][@section_index]["exercises"][@exercise_index] = replacement
    @workout.update!(structure: updated)

    replacement
  end

  private

  def sections
    Array(@workout.structure["sections"])
  end

  def call_llm(section, exercise)
    api_key = ENV.fetch("ANTHROPIC_API_KEY") { raise SwapError, "ANTHROPIC_API_KEY not set" }

    prompt = build_prompt(section, exercise)

    body = {
      model:       MODEL,
      max_tokens:  512,
      tools:       [ SWAP_TOOL ],
      tool_choice: { type: "any" },
      messages:    [ { role: "user", content: prompt } ]
    }

    http              = Net::HTTP.new(API_URI.host, API_URI.port)
    http.use_ssl      = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Post.new(API_URI.path)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = api_key
    request["anthropic-version"] = "2023-06-01"
    request.body = body.to_json

    response = http.request(request)
    raise SwapError, "API error #{response.code}" unless response.code.to_i == 200

    parsed     = JSON.parse(response.body)
    tool_block = parsed["content"].find { |b| b["type"] == "tool_use" }
    raise SwapError, "No replacement returned" unless tool_block

    tool_block["input"]
  end

  def build_prompt(section, exercise)
    workout_tags = @workout.tags.map(&:name).join(", ")
    other_names  = Array(section["exercises"])
                     .each_with_index
                     .reject { |_, i| i == @exercise_index }
                     .map { |e, _| e["name"] }

    lines = []
    lines << "You are a personal trainer. Suggest a replacement for one exercise in a workout."
    lines << ""
    lines << "Workout: #{workout_tags.presence || @workout.workout_type} · #{@workout.difficulty}"
    lines << "Section: \"#{section["name"]}\" (format: #{section["format"]})"
    lines << "Other exercises in section: #{other_names.join(", ")}" if other_names.any?
    lines << ""
    lines << "Exercise to replace: #{exercise["name"]}"
    lines << "Current specs: #{specs(exercise)}" if specs(exercise).present?
    lines << "Reason for swap: #{@reason}" if @reason
    lines << ""
    lines << "Requirements for the replacement:"
    lines << "- Same purpose in this section (similar muscle groups or energy system)"
    lines << "- Fits the #{section["format"]} format"
    lines << "- Genuinely different — not just a renamed version of \"#{exercise["name"]}\""
    lines << "- Realistic gym equipment"
    lines << "- Keep roughly the same reps/weight/distance unless the swap naturally calls for a change"
    lines << "- Avoid the stated reason if one was given" if @reason
    lines << ""
    lines << "Use the replace_exercise tool to return the single replacement."
    lines.join("\n")
  end

  def specs(exercise)
    parts = []
    parts << "#{exercise["reps"]} reps"       if exercise["reps"]
    parts << "#{exercise["calories"]} cal"    if exercise["calories"]
    parts << "#{exercise["distance_m"]}m"     if exercise["distance_m"]
    parts << "#{exercise["duration_s"]}s"     if exercise["duration_s"]
    parts << "#{exercise["weight_kg"]}kg"     if exercise["weight_kg"].to_f > 0
    parts.join(", ")
  end
end
