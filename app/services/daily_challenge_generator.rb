require "net/http"
require "json"

class DailyChallengeGenerator
  API_URL = "https://api.anthropic.com/v1/messages"

  def self.call(date: Date.current)
    new(date).generate
  end

  def initialize(date)
    @date = date
  end

  def generate
    return if DailyChallenge.exists?(date: @date)

    data = call_api
    DailyChallenge.create!(
      date:         @date,
      title:        data["title"],
      description:  data["description"],
      scoring_type: data["scoring_type"]
    )
  end

  private

  def call_api
    uri     = URI(API_URL)
    http    = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    request["anthropic-version"] = "2023-06-01"
    request.body = {
      model:      "claude-haiku-4-5-20251001",
      max_tokens: 500,
      tools:      [ challenge_tool ],
      tool_choice: { type: "auto" },
      messages:   [ { role: "user", content: prompt } ]
    }.to_json

    response = http.request(request)
    body     = JSON.parse(response.body)
    tool_use = body["content"]&.find { |c| c["type"] == "tool_use" }
    raise "Challenge generation failed: no tool call returned" unless tool_use
    tool_use["input"]
  end

  def challenge_tool
    {
      name: "create_challenge",
      description: "Create today's daily fitness challenge",
      input_schema: {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "Short punchy challenge name. E.g. 'The Centurion', 'Death by Thrusters', 'Chipper Monday'"
          },
          description: {
            type: "string",
            description: "Full workout prescription in 1–3 lines. Include reps, weights in kg, movements. End with how it is scored."
          },
          scoring_type: {
            type: "string",
            enum: %w[time reps rounds weight],
            description: "How the challenge is scored: time (fastest wins), reps/rounds (most wins), weight (heaviest wins)"
          }
        },
        required: %w[title description scoring_type]
      }
    }
  end

  def prompt
    <<~PROMPT
      Create a daily fitness challenge for #{@date.strftime("%A, %-d %B %Y")}.

      TARGET: completable in 8–15 minutes by a reasonably fit person. Keep it short and punchy.
      Mix scoring types across the week: some for time, some AMRAP (reps/rounds), occasionally max weight.
      Use common gym equipment: barbells, dumbbells, kettlebells, pull-up bar, box, rower/ski erg, assault bike. Runs are fine.
      Weights listed as rx/scaled (e.g. 40kg/27.5kg barbell or 24kg/16kg KB). Keep rx weights moderate — this is a daily challenge, not a competition.
      2–3 movements maximum.
      IMPORTANT: Total reps across the entire workout must not exceed 100. Count every rep including all rounds. People need to want to try it.
      Write clearly so anyone can follow it.

      Rep ladder formats are encouraged — use step counts in multiples of 3. Good options:
      - Descending: 21-15-9, 18-12-6, 15-9-3
      - Ascending: 3-6-9-12, 6-9-12-15
      - Triangle: 3-6-9-6-3, 6-9-12-9-6

      Good examples (notice the manageable total rep counts):
      - "21-15-9: Kettlebell Swings (24kg/16kg) + Push-ups. For time." (total: 90 reps ✓)
      - "18-12-6: Thrusters (40kg/27.5kg) + Burpee Box Jumps. For time." (total: 72 reps ✓)
      - "3-6-9-6-3: Hang Power Cleans (50kg/35kg) + Bar-facing Burpees. For time." (total: 54 reps ✓)
      - "AMRAP 10: 10 Cal Row + 8 DB Hang Clean & Jerk (22.5kg/15kg) + 6 Burpees" (open AMRAP, fine ✓)
      - "3 rounds for time: 400m Run + 10 Wall Balls (9kg/6kg) + 10 Box Jumps (60cm/50cm)" (total: 60 reps + runs ✓)
      - "Every 90 secs × 8: 5 Heavy Deadlifts. Score = heaviest set." (total: 40 reps ✓)
    PROMPT
  end
end
