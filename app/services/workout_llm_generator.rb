require "net/http"
require "json"

# WorkoutLLMGenerator uses Claude Haiku (via Anthropic API tool use) to generate
# a structured workout plan based on community context and user preferences.
#
# Usage:
#   workout = WorkoutLLMGenerator.call(
#     user:          current_user,
#     activity:      "Hyrox",
#     duration_mins: 30,
#     difficulty:    "intermediate"
#   )
#
# Returns a persisted Workout record or raises WorkoutGenerationError.
class WorkoutLLMGenerator
  # Maps tag slugs/names to context files in app/llm_context/
  CONTEXT_TAG_MAP = {
    "hyrox"              => "hyrox.md",
    "deka"               => "deka_fit.md",
    "deka-fit"           => "deka_fit.md",
    "deka-strong"        => "deka_strong.md",
    "deka-mile"          => "deka_mile.md",
    "deka-atlas"         => "deka_atlas.md",
    "dirty-dozen"        => "dirty_dozen.md",
    "crossfit"           => "crossfit.md",
    "functional-fitness"  => "functional.md",
    "functional-muscle"   => "functional_muscle.md",
    "hiit"               => "hiit.md",
    "bodyweight"         => "bodyweight.md",
    "meta-fit"           => "metafit.md",
    "metafit"            => "metafit.md",
    "metafit-bodyweight" => "metafit.md",
    "barry-s-bootcamp"   => "barrys.md",
    "barrys-bootcamp"    => "barrys.md",
    "barrys"             => "barrys.md",
    "f45"                => "f45.md"
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
    "hyrox"      => %w[SkiErg] + [ "Sled Push", "Sled Pull", "Burpee Broad Jumps",
                                   "Rowing", "Farmers Carry", "Sandbag Lunges", "Wall Balls" ],
    "deka"       => DEKA_ZONES,
    "deka-fit"   => DEKA_ZONES,
    "deka-strong" => DEKA_ZONES,
    "deka-mile"  => DEKA_ZONES,
    "deka-atlas" => [
      "Barbell Thrusters", "Bar-Facing Burpees Over Bar", "Surrender Lunges (weighted)",
      "Single Arm DB Ground to Overhead (alternating)", "Dumbbell Bear Crawl",
      "Weighted Sit-ups", "Farmer's Carry", "DB Shoulder to Overhead Press",
      "Jump Rope Single Unders", "Atlas Shoulder to Carry"
    ]
  }.freeze

  # Weighted count distribution: heavily favour 2-4, allow 1 and 5-6 occasionally.
  STATION_COUNT_WEIGHTS = [ 1, 2, 2, 3, 3, 3, 4, 4, 5, 6 ].freeze

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
    "Wall Balls"         => "100 reps | Open: 6kg to 10ft (M) / 4kg to 9ft (F) | Pro: 9kg to 10ft (M) / 6kg to 9ft (F)"
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
    "RAM Weighted Burpees" => "20 reps | 20kg (M) / 10kg (F)"
  }.freeze

  # Deka Atlas weights: { station => { peak: "...", foundation: "..." } }
  # Peak = advanced, Foundation = beginner, Intermediate = blend of both shown.
  DEKA_ATLAS_REFERENCE = {
    "Barbell Thrusters"                              => { peak: "20 reps | 45kg (M) / 30kg (F)", foundation: "20 reps | 30kg (M) / 20kg (F)" },
    "Bar-Facing Burpees Over Bar"                    => { peak: "20 reps", foundation: "20 reps" },
    "Surrender Lunges (weighted)"                    => { peak: "20 reps | 22.5kg (M) / 15kg (F)", foundation: "20 reps | 15kg (M) / 10kg (F)" },
    "Single Arm DB Ground to Overhead (alternating)" => { peak: "20 reps | 22.5kg (M) / 15kg (F)", foundation: "20 reps | 15kg (M) / 10kg (F)" },
    "Dumbbell Bear Crawl"                            => { peak: "40m | 22.5kg (M) / 15kg (F)", foundation: "40m | 15kg (M) / 10kg (F)" },
    "Weighted Sit-ups"                               => { peak: "20 reps | 15kg (M) / 9kg (F)", foundation: "20 reps | 10kg (M) / 7.5kg (F)" },
    "Farmer's Carry"                                 => { peak: "60m | 45kg each hand (M) / 32kg each hand (F)", foundation: "60m | 32kg each hand (M) / 22.5kg each hand (F)" },
    "DB Shoulder to Overhead Press"                  => { peak: "20 reps | 22.5kg (M) / 15kg (F)", foundation: "20 reps | 15kg (M) / 10kg (F)" },
    "Jump Rope Single Unders"                        => { peak: "100 reps", foundation: "100 reps" },
    "Atlas Shoulder to Carry"                        => { peak: "100m | 45kg (M) / 32kg (F)", foundation: "100m | 32kg (M) / 22.5kg (F)" }
  }.freeze

  EVENT_REFERENCE = {
    "hyrox"       => HYROX_REFERENCE,
    "deka"        => DEKA_REFERENCE,
    "deka-fit"    => DEKA_REFERENCE,
    "deka-strong" => DEKA_REFERENCE,
    "deka-mile"   => DEKA_REFERENCE,
    "deka-atlas"  => DEKA_ATLAS_REFERENCE
  }.freeze

  # Weighted training emphasis options — sampled randomly each generation.
  # Warm-up options — 4 distinct structures, weighted toward simple cardio (3 out of 10).
  WARMUP_OPTIONS = [
    # Structure 1: 5 mins easy cardio — 3 entries = 30%
    { label: "5 Min Easy Cardio",
      instruction: "One single cardio exercise for the full 5 minutes at an easy conversational pace. Use duration_s: 300. Choose one that suits the session: rowing machine, assault bike, ski erg, light jog, or (if no equipment) jumping jacks or step-touches. Nothing else — no additional exercises." },
    { label: "5 Min Easy Cardio",
      instruction: "One single cardio exercise for the full 5 minutes, easy effort. Use duration_s: 300. Pick something different from the session's main cardio — if the session is rowing-heavy, use the bike or ski erg instead. Nothing else." },
    { label: "5 Min Easy Cardio",
      instruction: "One single cardio exercise for the full 5 minutes. Use duration_s: 300. Options: assault bike, ski erg, rowing machine, light jog. Easy pace only — this is just to raise body temperature. Nothing else." },
    # Structure 2: 3 mins cardio + 3 activation exercises 30s each — 3 entries = 30%
    { label: "Cardio + Activation",
      instruction: "First exercise: easy cardio for 3 minutes (duration_s: 180) — row, bike, ski erg, or jog. Then 3 activation exercises, 30 seconds each (duration_s: 30), chosen to prime the muscles used in this session. Good options: glute bridges, dead bugs, inchworm to push-up, world's greatest stretch, banded clamshells, arm circles, leg swings, hip circles. 4 exercises total." },
    { label: "Cardio + Activation",
      instruction: "First exercise: easy cardio for 3 minutes (duration_s: 180) — vary the machine from the main session. Then 3 activation exercises at 30 seconds each (duration_s: 30) targeting what this session needs: lower body day → glute bridges, leg swings, hip circles. Upper body day → arm circles, band pull-aparts, shoulder rotations. Full body → inchworm, world's greatest stretch, jumping jacks. 4 exercises total." },
    { label: "Cardio + Activation",
      instruction: "First exercise: easy cardio for 3 minutes (duration_s: 180). Then 3 dynamic movements at 30 seconds each (duration_s: 30): pick from inchworm to push-up, walking lunges, lateral shuffles, hip 90/90 switches, thoracic rotations, arm crossovers. Choose movements relevant to what's in the main set. 4 exercises total." },
    # Structure 3: 6 activation exercises 45s each — 2 entries = 20%
    { label: "Activation Circuit",
      instruction: "6 activation exercises, 45 seconds each (duration_s: 45), no rest between. No cardio. Choose 6 low-intensity bodyweight movements that prepare the joints and muscles for this session. Examples: glute bridges, cat-cow, dead bugs, world's greatest stretch, leg swings, hip circles, thoracic rotation, arm circles, inchworm, air squats, shoulder rolls, lateral lunges." },
    { label: "Activation Circuit",
      instruction: "6 bodyweight activation exercises, 45 seconds each (duration_s: 45), flowing from one to the next with no rest. Pick 6 movements suited to this session's demands — mix lower body, upper body, and trunk. No equipment needed. Keep intensity very low — this is preparation, not training." },
    # Structure 4: 5 exercises 10 reps each x 2 rounds — 2 entries = 20%
    { label: "2-Round Bodyweight Circuit",
      instruction: "Use format: rounds with rounds: 2. 5 exercises, 10 reps each (reps: 10). Choose 5 low-intensity bodyweight exercises that cover the whole body: e.g. air squats, push-ups, glute bridges, inchworms, jumping jacks — or similar movements suited to the session. Easy pace, full range of motion, no rushing." },
    { label: "2-Round Bodyweight Circuit",
      instruction: "Use format: rounds with rounds: 2. 5 exercises, 10 reps each (reps: 10). Pick 5 movements relevant to the session's main muscle groups — vary them each time. Keep it easy and controlled. Examples: reverse lunges, push-up to downward dog, hip hinges, lateral lunges, shoulder circles with reach." },
    # Structure 5: resistance band activation — 1 entry
    { label: "Resistance Band Activation",
      instruction: "5–6 resistance band exercises, each 12–15 reps (use reps: 12 or reps: 15) or 30–45 seconds (use duration_s: 30 or duration_s: 45). Choose band movements that directly prime the muscles used in today's main session: lower body day → banded clamshells, banded glute bridges, banded squat walks, banded pull-throughs; upper body day → band pull-aparts, banded face pulls, banded external rotations, banded chest press; full body → mix of above. Use format: straight. Light resistance only — this is activation, not training." }
  ].freeze

  COOLDOWN_OPTIONS = [
    { label: "Lower Body Focus",
      duration_s: 45,
      instruction: "Prioritise hips, hamstrings, quads. 5 stretches, each duration_s: 45. Choose from: hip flexor stretch (kneeling lunge), pigeon pose or figure-four glute stretch, seated forward fold, standing quad stretch, lying spinal twist, butterfly stretch." },
    { label: "Upper Body Focus",
      duration_s: 45,
      instruction: "Prioritise chest, shoulders, lats. 5 stretches, each duration_s: 45. Choose from: chest opener (hands clasped behind back), cross-body shoulder stretch, doorframe pec stretch, thread the needle, child's pose with arms extended, lat stretch in doorframe." },
    { label: "Full Body Stretch",
      duration_s: 45,
      instruction: "Cover all major muscle groups. 5 stretches, each duration_s: 45. Pick one lower body, one hip, one hamstring, one chest/shoulder, one spine. Choose from: hip flexor lunge, pigeon pose, forward fold, chest opener, thoracic rotation, lying spinal twist." },
    { label: "Mobility Flow",
      duration_s: 30,
      instruction: "Movement-based cool-down rather than static holds. 5 exercises, each duration_s: 30. Use slow controlled reps described in notes: world's greatest stretch, deep squat to stand, cat-cow, thread the needle, downward dog with heel pedals." },
    { label: "Recovery Stretch",
      duration_s: 60,
      instruction: "Longer holds, very relaxed. 4 stretches only, each duration_s: 60. Choose from: child's pose, butterfly stretch, supine hamstring pull, lying spinal twist, pigeon pose. Fewer stretches held longer — designed to fully lower heart rate." }
  ].freeze

  # Mixed appears 4× (40%), each pure style appears 2× (20%).
  # Explicit session_notes from the athlete always override this.
  TRAINING_EMPHASES = [
    { label: "Mixed",
      instruction: "Blend strength and conditioning across the session — some heavier compound sets (6–10 reps), some higher-rep conditioning work (15–20 reps). No single style should dominate. Use varied formats and rest periods to hit different energy systems." },
    { label: "Mixed",
      instruction: "Varied session — mix heavier strength sets with moderate conditioning work. Alternate between lower-rep compound movements and higher-rep circuits. Keep the athlete guessing." },
    { label: "Mixed",
      instruction: "General fitness session — balance between strength, endurance, and movement quality. Don't lean heavily toward any single quality. A bit of everything." },
    { label: "Mixed",
      instruction: "Balanced effort session — moderate loads, moderate reps (8–15), mixed formats. Not a pure strength day and not a pure cardio day. The kind of session that makes you well-rounded." },
    { label: "Strength",
      instruction: "Strength focus — give each major lift its own dedicated section. Single-exercise sets only for the main work: e.g. '5 × 5 Back Squat', '4 × 6 Bench Press', '3 × 5 Deadlift'. Heavy loads (85–90% 1RM), long rest (2–3 min). No circuits — treat each lift as its own event. A conditioning finisher is fine at the end." },
    { label: "Strength",
      instruction: "Heavy lifting day — 2 or 3 big compound lifts, each in their own section with multiple sets and full rest. Examples: '5 × 3 Deadlift (heavy)', 'EMOM 10: 5 Thrusters (heavy)'. Low reps, high load, no rushing. Make it feel like a proper strength session, not a circuit." },
    { label: "Power",
      instruction: "Power development — moderate-to-heavy loads (70–80% 1RM) performed with explosive intent. Use single-exercise sections for the main lifts (e.g. '4 × 5 Power Clean', 'EMOM 8: 5 Box Jumps + 3 Push Press'). 5–8 reps, fast concentric, controlled eccentric. Rest 60–90s to maintain power output." },
    { label: "Power",
      instruction: "Explosive session — anchor the main set around 1–2 heavy dynamic lifts in dedicated sections (e.g. '5 × 4 Hang Power Clean', '4 × 6 KB Swing heavy'). Complement with plyometrics. Fast and purposeful, not a circuit grind." },
    { label: "Conditioning",
      instruction: "Conditioning focus — higher rep ranges (15–25+), shorter rest, lighter loads. Circuit-style or interval-based. The metabolic challenge is the goal — heart rate should stay elevated throughout. Unbroken sets where possible." },
    { label: "Conditioning",
      instruction: "Metabolic session — keep rest short and reps high. Lighter weights, fast transitions, sustained effort. Think: sweat, breathing hard, and muscular fatigue from volume rather than load." }
  ].freeze

  API_URI = URI("https://api.anthropic.com/v1/messages").freeze
  MODEL   = "claude-haiku-4-5-20251001".freeze

  # Lightweight tool used by the research pass (first prompt) to return structured
  # program info for any tag we don't have a pre-written context file for.
  RESEARCH_TOOL_DEFINITION = {
    name: "describe_fitness_program",
    description: "Describe a fitness training program or style in enough detail to accurately recreate a session.",
    input_schema: {
      type: "object",
      required: %w[description session_structure cardio_style strength_style typical_exercises equipment signature_characteristics],
      properties: {
        description:               { type: "string", description: "2-3 sentence overview of what this program is and who it's for" },
        session_structure:         { type: "string", description: "Exactly how a typical class/session flows from start to finish — describe each phase or block in order with approximate timing. E.g. 'Barry's: 5-min warmup → 25-min treadmill block (intervals alternating sprints and recovery) → 25-min floor block (dumbbell strength circuits) → 5-min stretch'" },
        cardio_style:              { type: "string", description: "What the cardio component looks like — equipment used, interval structure, intensity patterns, pacing style" },
        strength_style:            { type: "string", description: "What the strength/resistance component looks like — rep ranges, loading, circuit style, rest periods, intensity" },
        typical_exercises:         { type: "array",  items: { type: "string" }, description: "15-20 specific exercises used in this program, with typical rep ranges or durations where known. E.g. 'Dumbbell chest press — 3×12', 'Treadmill sprint intervals — 30s on / 30s off × 8'" },
        equipment:                 { type: "array",  items: { type: "string" }, description: "Equipment typically available and used in this program" },
        signature_characteristics: { type: "array",  items: { type: "string" }, description: "3-5 things that make this program distinctive — what gives it its feel and identity" }
      }
    }
  }.freeze

  TOOL_DEFINITION = {
    name: "create_workout",
    description: "Create a structured workout plan in the required JSON format.",
    input_schema: {
      type: "object",
      required: %w[name duration_mins difficulty structure],
      properties: {
        name:          { type: "string",  description: "Punchy, imaginative workout name (2-4 words). Draw from a wide range of styles: feelings ('Tuesday's Regret', 'Happy Lungs'), imagery ('Desert Rain', 'Two Left Feet'), irony ('Light and Easy', 'Quick One'), structure ('The Long Way Round', 'Death By Threes'), mythology/slang ('The Minotaur', 'Fried Eggs'), or anything else vivid and memorable. Avoid over-relying on clichéd gym words like Iron, Gauntlet, Grinder, Thunder, Beast, Inferno, Blitz, Crusher, Destroyer, Titan — they can work occasionally but should not be your default. Avoid generic names like 'Full Body Workout'." },
        duration_mins: { type: "integer", description: "Total workout duration in minutes" },
        difficulty:    { type: "string",  enum: Workout::DIFFICULTIES },
        structure: {
          type: "object",
          required: [ "sections" ],
          properties: {
            goal: { type: "string", description: "One-sentence coaching cue for the session" },
            sections: {
              type: "array",
              items: {
                type: "object",
                required: %w[name format],
                properties: {
                  name:               { type: "string" },
                  format:             { type: "string", enum: %w[straight amrap rounds emom tabata for_time ladder mountain matrix hundred], description: "straight=sets with rest, rounds=multiple rounds of the same set, amrap=as many rounds as possible in a time cap, emom=every minute on the minute, tabata=20s work/10s rest×8, for_time=complete prescribed reps/distance as fast as possible (record finishing time), ladder/mountain=reps/distance change each round, matrix=progressive exercise combination (add then remove exercises each round: A → A+B → A+B+C → B+C → C), hundred=100 reps of a single exercise for time (The Centurion)" },
                  duration_mins:      { type: "integer" },
                  rounds:             { type: "integer" },
                  rest_secs:          { type: "integer", description: "Rest in seconds after each round. Must be 30, 45, or 60 only." },
                  emom_style:         { type: "string", enum: %w[circuit rotating], description: "EMOM sections only. circuit=all exercises done together each minute (max 3 exercises, rep cap applies). rotating=one exercise per minute cycling through the list (duration_mins must be a multiple of exercise count)." },
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
                      required: [ "name" ],
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

  def self.call(user:, duration_mins:, difficulty:, activity: nil, group_tag_name: nil, source_workout: nil, session_notes: nil, prompt_mode: :full, **_legacy)
    new(user: user, activity: activity, group_tag_name: group_tag_name, duration_mins: duration_mins, difficulty: difficulty, source_workout: source_workout, session_notes: session_notes, prompt_mode: prompt_mode).call
  end

  def initialize(user:, duration_mins:, difficulty:, activity: nil, group_tag_name: nil, source_workout: nil, session_notes: nil, prompt_mode: :full, **_legacy)
    @user           = user
    @activity       = activity.presence
    @activity_slug  = @activity&.parameterize
    @group_tag_name = group_tag_name.presence
    @duration_mins  = duration_mins.to_i
    @difficulty     = difficulty
    @source_workout = source_workout
    @session_notes  = session_notes.presence
    @prompt_mode    = prompt_mode.to_sym
  end

  def call
    if @source_workout
      prompt       = build_remix_prompt
      workout_data = call_llm(prompt)
      create_workout(workout_data)
    elsif @prompt_mode == :examples
      example_workouts = fetch_top_liked_examples
      prompt           = build_example_prompt(example_workouts)
      workout_data     = call_llm(prompt)
      workout_data     = validate_and_fix(workout_data)
      workout_data     = collapse_duplicate_exercises(workout_data)
      workout_data     = collapse_set_notation(workout_data)
      create_workout(workout_data)
    else
      context_workouts  = fetch_context
      program_research  = research_unknown_program
      recent_names      = fetch_recent_workout_names
      recent_fm_formats = fetch_recent_fm_formats
      prompt            = build_prompt(context_workouts, program_research, recent_names, recent_fm_formats)
      workout_data     = call_llm(prompt)
      workout_data     = validate_and_fix(workout_data)
      workout_data     = collapse_duplicate_exercises(workout_data)
      workout_data     = collapse_set_notation(workout_data)
      create_workout(workout_data)
    end
  end

  private

  def fetch_context
    # Event sessions (Hyrox, Deka) skip community workouts — they all look the same
    # and act as a strong template that prevents variety.
    return [] if event_session?

    # Group tag takes full priority — draw from a pool and sample randomly for variety.
    if @group_tag_name
      group_tag = Tag.find_by(slug: @group_tag_name.parameterize)
      if group_tag
        ids = Workout.joins(:taggings)
                     .where(taggings: { tag_id: group_tag.id })
                     .left_joins(:workout_likes)
                     .group(:id)
                     .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
                     .limit(20).pluck(:id)
        return Workout.where(id: ids.sample(3)) if ids.any?
      end
    end

    # Fetch popular workouts by activity, then sample randomly
    ids = @activity ? Workout.most_liked_with_activity(@activity, limit: 20).pluck(:id) : []

    # Still thin? Fall back to globally popular workouts
    if ids.size < 3
      ids = Workout.left_joins(:workout_likes)
                   .group(:id)
                   .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
                   .limit(20)
                   .pluck(:id)
    end

    return [] if ids.empty?
    Workout.where(id: ids.sample(3))
  end

  # Fetches the 5 most-liked workouts matching the current tags for use as few-shot examples.
  # Unlike fetch_context (which samples 3 randomly from top 20), this returns the actual top 5
  # ordered by like count, so the user's multi-likes act as quality weighting.
  def fetch_top_liked_examples
    return Workout.left_joins(:workout_likes).group(:id).order(Arel.sql("COUNT(workout_likes.id) DESC")).limit(5) unless @activity

    Workout.most_liked_with_activity(@activity, limit: 5)
  end

  # Builds a minimal prompt that relies on example workouts instead of extensive rules.
  # The idea: show the LLM 5 high-quality workouts and ask it to create something fresh
  # in the same style, rather than micromanaging every detail with rules.
  def build_example_prompt(example_workouts)
    main_name = @activity || "general fitness"

    examples_json = example_workouts.map do |w|
      {
        name: w.name,
        activity: w.activity,
        duration_mins: w.duration_mins,
        difficulty: w.difficulty,
        structure: w.structure
      }
    end

    sections = []

    sections << <<~ROLE
      You are an expert personal trainer who writes creative, fun, and effective gym workouts.
    ROLE

    user_context = build_user_context
    sections << user_context if user_context.present?

    sections << <<~TASK
      Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} session.
    TASK

    if example_workouts.any?
      sections << <<~EXAMPLES
        Here are #{example_workouts.size} example workouts that the athlete loves. Study their structure, exercise selection, format variety, naming style, and rep schemes — then create something FRESH in the same spirit. Do not copy them directly, but match their quality and style:

        #{JSON.pretty_generate(examples_json)}
      EXAMPLES
    end

    sections << <<~RULES
      Use the create_workout tool. Key guidelines:
      - Give it a punchy, memorable name (2-4 words) — creative, not generic
      - Use a variety of section formats (don't repeat the same format back-to-back)
      - Include a warm-up and cool-down
      - Be specific with reps, distances, and weights
      - Rep counts should be clean numbers (even or multiples of 5)
      - NEVER use numbered block prefixes like "Block 1:", "Block 2:" in section names — use creative, descriptive names instead
      - Make it genuinely fun and challenging — the kind of workout people talk about afterwards
    RULES

    sections.join("\n")
  end

  # Returns the names of the user's 5 most recent workouts that share the current main tag.
  # Used to avoid repeating words or themes in the new workout name.
  def fetch_recent_workout_names
    scope = @user.workouts.where(status: "active").order(created_at: :desc)
    scope = scope.joins(:activity).where(activities: { name: @activity }) if @activity
    scope.limit(5).pluck(:name).compact
  end

  # For Functional Muscle sessions: extract block types and key exercises from the
  # last 3 sessions so the LLM can deliberately vary the structure and compound choices.
  def fetch_recent_fm_formats
    return nil unless @activity_slug == "functional-muscle"

    recent = @user.workouts
                  .joins(:activity).where(activities: { name: @activity }, status: "active")
                  .order(created_at: :desc)
                  .limit(3)

    return nil if recent.empty?

    summaries = recent.map do |w|
      sections = Array(w.structure&.dig("sections"))
      formats  = sections.map { |s| s["format"] }.compact.uniq
      tabatas  = sections.select { |s| s["format"] == "tabata" }
                         .flat_map { |s| Array(s["exercises"]).map { |e| e["name"] } }
      machines = sections.select { |s| s["name"].to_s.match?(/strength/i) }
                         .flat_map { |s| Array(s["exercises"]).map { |e| e["name"] } }
      finisher = sections.find { |s| s["format"] == "hundred" }&.dig("exercises", 0, "name")

      parts = [ "\"#{w.name}\"" ]
      parts << "blocks: #{formats.join(", ")}" if formats.any?
      parts << "tabata compounds: #{tabatas.join("; ")}" if tabatas.any?
      parts << "machines: #{machines.join(", ")}" if machines.any?
      parts << "finisher: #{finisher}" if finisher
      parts.join(" | ")
    end

    summaries.join("\n")
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
      kept = exercises.first.dup
      kept.delete("notes") if kept["notes"].to_s.match?(/\Aset\s*\d+\z/i)
      section["exercises"] = [ kept ]
    end

    workout_data
  end

  # Detects sections where the LLM repeated the same exercise multiple times
  # (the "Set 1 / Set 2 / Set 3" anti-pattern). Deduplicates by name, strips
  # "Set N" notes, and sets rounds on the section to the highest repeat count.
  SET_NOTE_PATTERN = /\A\s*set\s*\d+\b/i.freeze

  def collapse_set_notation(workout_data)
    Array(workout_data.dig("structure", "sections")).each do |section|
      exercises = Array(section["exercises"])
      next if exercises.size < 2

      names = exercises.map { |e| e["name"] }
      next if names.uniq.size == names.size  # all unique — nothing to collapse

      seen  = {}
      deduped = []
      exercises.each do |e|
        name = e["name"]
        if seen[name]
          seen[name] += 1
        else
          seen[name] = 1
          kept = e.dup
          kept.delete("notes") if kept["notes"].to_s.match?(SET_NOTE_PATTERN)
          deduped << kept
        end
      end

      max_repeats = seen.values.max
      if max_repeats > 1 && section["rounds"].to_i <= 1
        section["rounds"] = max_repeats
        section["format"] = "rounds" if section["format"] == "straight"
      end
      section["exercises"] = deduped
    end

    workout_data
  end

  def build_difficulty_guidance
    case @difficulty
    when "beginner"
      <<~DIFF
        ## Difficulty: Beginner
        This is a beginner session — scale everything accordingly:
        - **Reps per set:** 10–15 for bodyweight/conditioning; 8–12 for weighted strength work
        - **Weights:** ~50–60% of 1RM for barbell lifts; light dumbbells (5–10kg); bodyweight where possible
        - **Rest:** 90–120s between strength sets; 60–90s between conditioning intervals
        - **Movement complexity:** stick to simple, low-skill movements — goblet squats not back squats, dumbbell rows not cleans, ring rows not muscle-ups. No Olympic lifting.
        - **Volume:** keep total working sets low (2–3 per exercise). Do not stack too many exercises per section.
        - **EMOM:** ≤6 total reps per minute across all exercises
        - **Intensity:** comfortable effort, never redline. Focus on learning the movements.
      DIFF
    when "intermediate"
      <<~DIFF
        ## Difficulty: Intermediate
        This is an intermediate session — the athlete can handle solid effort and moderate complexity:
        - **Reps per set:** 8–12 for strength; 12–20 for conditioning; higher for bodyweight
        - **Weights:** ~65–75% of 1RM for barbell lifts; moderate dumbbells/kettlebells (12–24kg)
        - **Rest:** 60–90s between strength sets; 45–60s between conditioning intervals
        - **Movement complexity:** barbell squats, deadlifts, press variations fine. Simple kettlebell and gymnastics skills (kipping pull-ups, box jumps, KB swings) are appropriate. Avoid heavy Olympic lifting unless the session specifically calls for it.
        - **Volume:** 3–4 working sets per exercise. Sections can have 2–4 exercises.
        - **EMOM:** ≤9 total reps per minute across all exercises
        - **Intensity:** strong effort, should feel hard but sustainable. Some redline moments in finishers are fine.
      DIFF
    when "advanced"
      <<~DIFF
        ## Difficulty: Advanced
        This is an advanced session — the athlete is well-conditioned and can handle high volume, heavy loads, and complex movements:
        - **Reps per set:** 5–8 for heavy strength (85–90% 1RM); 15–25 for conditioning; higher for lighter bodyweight work
        - **Weights:** ~75–90% of 1RM for heavy work; RX competition weights for conditioning (e.g. 24kg KB, 20kg wall ball); heavy carries and sleds
        - **Rest:** 45–60s between conditioning sets; 90–120s only for true max-effort lifts
        - **Movement complexity:** all barbell movements including cleans, snatches, thrusters at moderate-heavy loads. Gymnastics (strict muscle-ups, handstand push-ups, toes-to-bar). Complex kettlebell work.
        - **Volume:** 4–5 working sets. Sections can be dense with 3–5 exercises. Total working time should feel relentless.
        - **EMOM:** ≤12 total reps per minute across all exercises
        - **Intensity:** should be genuinely hard. Redline in finishers and for-time sections is expected and appropriate.
      DIFF
    else
      ""
    end
  end

  def build_training_emphasis
    emphasis = TRAINING_EMPHASES.sample
    "## Training Emphasis: #{emphasis[:label]}\n#{emphasis[:instruction]}"
  end

  def build_warmup_cooldown
    if @duration_mins < 30
      return <<~WC
        ## Warm-Up Approach: Light Cardio (3 min)
        Use a single exercise: 3 minutes of easy cardio (e.g. light jog, easy row, easy bike). format: straight, duration_mins: 3, one exercise with duration_s: 180.

        ## Cool-Down Approach: Quick Stretch (2 min)
        Use a single exercise: 2 minutes of loosening off and stretching. format: straight, duration_mins: 2, one exercise with duration_s: 120.
      WC
    end

    # When session notes suggest limited equipment, skip warm-ups that reference machines
    warmup_pool = if equipment_limited?
      WARMUP_OPTIONS.select { |w| w[:label].match?(/Activation|Bodyweight|Band/) }
    else
      WARMUP_OPTIONS
    end
    warmup_pool = WARMUP_OPTIONS if warmup_pool.empty? # safety fallback

    warmup   = warmup_pool.sample
    cooldown = COOLDOWN_OPTIONS.sample
    <<~WC
      ## Warm-Up Approach: #{warmup[:label]}
      #{warmup[:instruction]}

      ## Cool-Down Approach: #{cooldown[:label]}
      #{cooldown[:instruction]}
      IMPORTANT: every cool-down exercise must use duration_s: #{cooldown[:duration_s]} — all the same, no exceptions. Do not mix durations.
    WC
  end

  def build_prompt(context_workouts, program_research = nil, recent_names = [], recent_fm_formats = nil)
    main_name  = @activity || "general fitness"
    cc_config  = fm_continuous_circuit_config  # reuse same pool for all session types

    selected_stations = pick_event_stations
    station_constraint = if selected_stations
      " Anchor movements for this session (must appear in the main set): #{selected_stations.join(", ")}. Supplement freely with exercises from the #{main_name} training toolkit."
    end

    task_sentence = "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} session.#{station_constraint}"

    sections = []

    sections << <<~BASE
      You are a personal trainer specialising in writing fun and exciting workouts that improve people's overall fitness.

      #{task_sentence}
    BASE

    sections << build_difficulty_guidance
    sections << build_training_emphasis
    sections << build_warmup_cooldown

    if selected_stations
      # For event sessions with a station selection: inject the training philosophy
      # from the context file but NOT the station table (which causes the LLM to
      # treat it as a checklist). Station reference is injected separately below.
      sport_context = load_sport_context([ @activity ].compact)
      if sport_context.present?
        # Strip the station table (the block between "## The N Stations" and "## Training")
        philosophy_only = sport_context.gsub(/##\s+The \d+ (?:Stations|Zones).*?(?=##\s+Training)/m, "")
        sections << philosophy_only if philosophy_only.strip.present?
      end
      station_ref = build_station_reference(selected_stations)
      sections << station_ref if station_ref
    else
      sport_context = load_sport_context([ @activity ].compact)
      sections << sport_context if sport_context.present?
    end

    if program_research
      sections << build_program_research_context(program_research)
    end

    if context_workouts.any?
      context_json = context_workouts.map do |w|
        { name: w.name, activity: w.activity, duration_mins: w.duration_mins,
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

    if @session_notes.present?
      sections << <<~NOTES
        ## *** ATHLETE'S SESSION FOCUS — HIGHEST PRIORITY ***
        The athlete has specifically requested the following focus for this session. This is the SINGLE MOST IMPORTANT instruction — it overrides default exercise selection and must be clearly reflected in the exercises chosen:

        >>> #{@session_notes} <<<

        How to apply this:
        - "strength" / "hypertrophy" / "bodybuilding" / "muscle" → STRUCTURE LIKE A REAL LIFTING SESSION: single-exercise sections with heavy sets (e.g. "5×5 Back Squat", "4×8 Romanian Deadlift", "4×10 Overhead Press") are the backbone. Each major compound gets its OWN section with proper rounds and rest (60-90s). Accessory work can be supersets (2 exercises) but NOT large circuits. Minimise cardio — warm-up and cool-down only. At least 70% of the session should be dedicated barbell/dumbbell strength work.
        - "cardio focus" → sustained machine work (rower, ski, bike, run), high-rep bodyweight, AMRAPs, EMOMs. At least 60% of the session should be cardio/conditioning.
        - "sled focus" → sled pushes, sled pulls, sled drags must appear in MULTIPLE sections, as the primary exercises. The sled is the centrepiece — not a single appearance.
        - "burpee focus" → burpee variations (burpee box jump-overs, burpee pull-ups, bar-facing burpees, lateral burpees) must appear in MULTIPLE sections. Build the session around burpees.
        - Any specific exercise/equipment mentioned → that exercise must appear in at least 2-3 sections as a primary movement.
        - Injury mentions → avoid exercises that load or stress that area
        - Equipment constraints → use only the specified equipment throughout
        - The workout NAME should reflect this focus (e.g. a sled focus session should reference sleds in the name)
      NOTES
    end

    sport_rule          = sport_purity_rule
    core_rule           = core_section_rule
    pace_limits         = pace_limit_rule
    structure_rule      = build_session_structure
    training_rule       = training_rep_rule
    race_sim_rule       = race_simulation_rule
    func_muscle_rule    = functional_muscle_rule
    fm_archetype        = fm_session_archetype
    equipment_rule      = build_equipment_rule
    station_rule    = if selected_stations
      "- ANCHOR MOVEMENTS: #{selected_stations.join(", ")} must be central to the main set. Complement them with toolkit exercises from the sport context — create a complete, varied workout, not a drill of the anchor movements repeated in every section."
    end

    sections << <<~RULES
      Use the create_workout tool. Requirements:
      #{race_sim_rule}
      #{fm_archetype}
      #{func_muscle_rule}
      #{structure_rule}
      #{station_rule}
      #{equipment_rule}
      - Warm-up: #{@duration_mins <= 30 ? "3 minutes (format: straight, duration_mins: 3). Keep it simple — 1 exercise, steady cardio only." : "5 minutes (format: straight, duration_mins: 5). Use the Warm-Up Approach specified above — follow it exactly."}
      - Cool-down: #{@duration_mins <= 30 ? "2 minutes (format: straight, duration_mins: 2). Keep it minimal — just a note to loosen off and stretch, no detailed holds." : "5 minutes (format: straight, duration_mins: 5). Use the Cool-Down Approach specified above. No reps or distances — hold times only, described in notes (e.g. \"30s each side\")."}.
      - Main sets: do NOT set duration_mins on main sets — let the reps, rounds, and format define the work. Only amrap and emom sections need a duration_mins (their time cap). A short punchy finisher (e.g. Tabata, The Hundred/Centurion, for_time sprint) is a welcome extra at the end of the main work.
      #{core_rule}
      #{training_rule}
      - Rep counts and calorie targets must be "clean" numbers — even numbers (2, 4, 6, 8, 10, 12, 16, 20…) or multiples of 5 (5, 10, 15, 20, 25…). Never use odd, awkward counts like 13, 7, 11, 17, or 19. When scaling from competition volumes, round to the nearest clean number.
      - Be specific with reps, distances, and weights
      - SECTION NAMES MUST BE ACCURATE: never mention an exercise or activity in a section name unless it actually appears in that section's exercises. "Run + Station" must contain running. "Sled Circuit" must contain sled work. If unsure, use a generic evocative name instead.
      - NEVER use numbered block prefixes like "Block 1:", "Block 2:", "Block 3:" or "Part 1:", "Part 2:" in section names. Use creative, descriptive names instead.
      - Give it a punchy, memorable name — something a gym community would actually call it. Be creative and unpredictable: draw from feelings, imagery, places, days, animals, weather, mythology, slang — anything vivid. Actively vary the style each time (e.g. a cheeky two-worder one time, a dramatic three-worder the next, a dry/ironic name after that). BANNED WORDS — never use: Iron, Gauntlet, Grinder, Thunder, Beast, Inferno, Blitz, Crusher, Destroyer, Titan. #{recent_names.any? ? "The user's recent workout names are: #{recent_names.map { |n| "\"#{n}\"" }.join(", ")}. Do NOT reuse any word or theme from these." : ""}
      #{recent_fm_formats.present? ? "- RECENT SESSIONS — the user's recent Functional Muscle sessions were:\n#{recent_fm_formats.lines.map { |l| "        #{l}" }.join}\n      Use this to avoid repetition: pick different strength machines from the ones listed, pick a different Pilates 100 exercise, and vary the tabata compounds. Block types (12-min, ladder etc) can repeat if they fit — but machines and finisher should rotate." : ""}
      #{sport_rule}
      #{pace_limits}
      - FORMAT SELECTION — choose the best format for each section. VARIETY IS MANDATORY: no two adjacent sections may share the same format, and across the full session you must use at least 3 different formats. Do not default to rounds and tabata for everything — ladders, amraps, rotating EMOMs, hundreds, and for_time efforts are equally valid and make sessions far more interesting. Here are the available formats:
        * tabata — high-intensity cardio bursts or bodyweight finishers. 20s on / 10s off × 8 rounds = exactly 4 minutes. Set duration_mins: 4. Do NOT set reps, calories, or distance_m on tabata exercises — the 20s interval is the only constraint. You may specify weight_kg where relevant. EXERCISE COUNT RULES: exercises in a tabata section must be exactly 1, 2, 4, or 8 (factors of 8). Multiple exercises ROTATE through the 8 rounds — 2 exercises = ABABABAB (4 rounds each), 4 exercises = ABCDABCD (2 rounds each), 8 exercises = each done once. Use a SEPARATE tabata section if you want two independent tabatas.
        * emom — two distinct styles, set emom_style accordingly:
          - circuit (emom_style: "circuit"): all exercises done together each minute, rest for the remainder. Max 2 exercises (3 only if all bodyweight). The work must be completable in ~40 seconds to leave rest. HARD REP CAP per minute: beginner ≤8, intermediate ≤12, advanced ≤16 total reps across all exercises. CARDIO MACHINE BAN: Do NOT include SkiErg, Rowing Machine, or Air/Assault Bike in a circuit EMOM — they take too long and leave no time for the other exercise(s). Use cardio machines in rotating EMOMs instead, where they get a full minute. E.g. "EMOM 10: 5 thrusters + 5 burpees". Set duration_mins for the total time cap.
          - rotating (emom_style: "rotating"): THE CONTINUOUS CIRCUIT — a different exercise each minute, cycling non-stop through the full duration. Each exercise fills its own minute — no reps, no calories, no distance, no duration on exercises. Do NOT add minute-assignment notes like "Min 1, 3, 5:" — exercises just rotate in order. Coaching notes only (e.g. "explosive hip extension"). duration_mins MUST be a multiple of the exercise count. *** FOR THIS SESSION use: #{cc_config} *** Mix one cardio machine + strength/skill movements + an active recovery or core exercise for best effect. The cardio minute is the "recovery" — keep it to a sustainable hard effort, not a sprint.
        * amrap — clock-driven main set. Complete as many rounds as possible in the time cap. Scores rounds+reps. Great for mixed-modal circuits, testing work capacity. E.g. "AMRAP 12: 10 KB swings + 8 box jumps + 6 burpees". Use freely — this is underused and highly effective.
        * for_time — complete the prescribed work as fast as possible, record finishing time. When using multiple exercises, always set rounds: 3 minimum — a single pass through a mixed circuit is not a meaningful conditioning block. E.g. "3 rounds for time: 20 cal SkiErg + 20 KB swings + 12 box jumps", "5 rounds: 400m row + 10 burpees". Single-exercise for_time (e.g. 100 cal row for time) can use rounds: 1.
        * hundred — "The Centurion": exactly 100 reps of a single exercise, done for time. Set reps: 100 on the one exercise. A genuinely brutal and satisfying finisher for ANY session type — not just Functional Muscle. Works for: KB swings, wall balls, box jumps, push-ups, burpees, thrusters, air squats, sit-ups, rowing calories, ski calories. Use it as a punchy end to a main set when you want one last gut-check. Not just a gimmick — it's a legitimate conditioning tool.
        * rounds — structured circuit with planned rest. Good for strength work, controlled conditioning with recovery between efforts. ALWAYS set rounds explicitly (e.g. rounds: 5 for 5×5 strength, rounds: 3 for a conditioning circuit) — never leave rounds absent or zero.
        * ladder / mountain — rep or distance progression each rung. Highly effective and underused — use it regularly, not just occasionally. ONLY when all exercises share the same metric AND the step size is realistic:
          - reps: step 1–5. E.g. start:10 end:1 step:1 = 10,9,8...1 reps.
          - calories: step 5–10. E.g. start:20 end:5 step:5 = 20,15,10,5 cal.
          - distance_m: step 10–20. E.g. start:40 end:20 step:10 = 40m,30m,20m.
          - mountain: ascend then descend. E.g. start:5 peak:15 end:5 step:5 = 5,10,15,10,5 reps. Great for barbell strength work (Bears, cleans, deadlifts).
          - INVALID: mixing reps, distance, and calorie exercises in the same ladder.
        * straight — fixed sets with rest. Use for simple warm-ups or isolated single exercises.
        * matrix — progressive exercise combinations. List 3–5 exercises in order. The section builds up then strips back: for 3 exercises: A, A+B, A+B+C, B+C, C. For 4: A, A+B, A+B+C, A+B+C+D, B+C+D, C+D, D. For 5: A, A+B, A+B+C, A+B+C+D, A+B+C+D+E, B+C+D+E, C+D+E, D+E, E. IMPORTANT: all exercises must use the same metric — either all reps (same count each) or all duration_s (same seconds each). Prefer duration_s: 30 for each exercise most of the time — this is the most common Metafit style. Set rest_secs for the rest between each combination (typically 30–60s).
      - EXERCISE VARIETY ACROSS THE SESSION: never use the same base movement in more than one section. If Back Squat appears in one section, do NOT use Back Squat (or Paused Back Squat, or any squat variation on a barbell) in another section — pick a different compound like Front Squat, Deadlift, or Overhead Press instead. The whole session should expose the athlete to as many different movement patterns as possible.
      - NEVER repeat the same exercise as multiple entries in the exercises array. This is a critical mistake — do NOT list "Bench Press (Set 1)", "Bench Press (Set 2)", "Bench Press (Set 3)" as three separate entries. Instead, use a single entry and set rounds: 3 on the section. Notes like "Set 1:", "Set 2:" in exercise notes are forbidden.
      - SINGLE-EXERCISE SECTIONS are valid and often better than circuits, especially for strength and power work. A section with just one exercise is perfectly correct: e.g. '5 × 5 Deadlift (heavy)', 'EMOM 10: 8 Thrusters', '4 × 8 Romanian Deadlift'. Do not feel obligated to bundle every movement into a multi-exercise circuit. HOWEVER: a single-exercise section MUST always use multiple sets (rounds: 3 minimum) or a timed modality (emom/amrap/for_time). BANNED: a section with 1 exercise and rounds ≤ 2 (or no rounds). This is always wrong. Every section must represent real training volume, not a single isolated set.
      - NEVER list the same exercise more than once in a section's exercises array. If you need the same movement repeated (e.g. 5 × 25m Freestyle), use rounds: 5 with a single exercise entry — not 5 separate entries. Duplicate entries are always wrong.
      #{@session_notes.present? ? "\n      *** REMINDER — ATHLETE'S SESSION FOCUS (HIGHEST PRIORITY): \"#{@session_notes}\" — The exercises you select MUST clearly reflect this focus. If the athlete asked for sleds, use sleds heavily. If they asked for strength, programme heavy barbell work. Do not just change the name — change the actual exercises. ***" : ""}
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

  # Returns a bullet-point rule for explicit exclusions (e.g. "no-run" minor tag).
  # Builds a hard equipment constraint from session notes mentioning specific equipment.
  # Parses what the athlete HAS, then explicitly bans everything else.
  def build_equipment_rule
    return nil unless @session_notes.present?

    notes_lower = @session_notes.downcase

    # Map of detectable equipment → canonical name
    equipment_map = {
      "olympic bar" => "olympic barbell", "barbell" => "barbell",
      "dumbbell" => "dumbbells", "dumbbells" => "dumbbells",
      "kettlebell" => "kettlebells", "kettlebells" => "kettlebells",
      "squat rack" => "squat rack", "power rack" => "squat rack", "rack" => "squat rack",
      "bench" => "bench", "flat bench" => "bench", "adjustable bench" => "bench",
      "pull-up bar" => "pull-up bar", "pull up bar" => "pull-up bar",
      "resistance band" => "resistance bands", "bands" => "resistance bands",
      "trx" => "TRX/suspension trainer", "suspension" => "TRX/suspension trainer",
      "plates" => "weight plates",
      "cable machine" => "cable machine", "cables" => "cable machine",
      "rower" => "rowing machine", "rowing machine" => "rowing machine",
      "ski erg" => "SkiErg", "skierg" => "SkiErg",
      "assault bike" => "assault bike", "air bike" => "assault bike", "bike" => "stationary bike",
      "treadmill" => "treadmill", "battle rope" => "battle ropes", "sled" => "sled",
      "box" => "plyo box", "jump box" => "plyo box",
      "medicine ball" => "medicine ball", "med ball" => "medicine ball",
      "wall ball" => "wall ball"
    }

    detected = equipment_map.each_with_object(Set.new) do |(keyword, canonical), set|
      set << canonical if notes_lower.include?(keyword)
    end

    # Also detect "home gym" or "hotel" as environment hints
    home_gym = notes_lower.include?("home gym") || notes_lower.include?("garage gym")
    hotel    = notes_lower.include?("hotel")

    return nil if detected.empty? && !home_gym && !hotel

    # Build banned list — common gym equipment NOT in the detected set
    all_gym_equipment = [
      "rowing machine", "SkiErg", "assault bike", "stationary bike", "treadmill",
      "battle ropes", "sled", "cable machine", "plyo box", "wall ball", "medicine ball",
      "GHD machine", "leg press", "lat pulldown", "pec deck"
    ]
    banned = all_gym_equipment.reject { |e| detected.include?(e) }

    available_str = detected.any? ? detected.to_a.sort.join(", ") : "bodyweight only"

    <<~RULE.strip
      - *** EQUIPMENT CONSTRAINT (HARD LIMIT) ***:
        The athlete is training in a #{home_gym ? "home gym" : hotel ? "hotel" : "limited equipment"} setting.
        AVAILABLE: #{available_str} + bodyweight exercises (always allowed).
        BANNED (athlete does NOT have these): #{banned.join(", ")}.
        Every exercise must be doable with ONLY the available equipment or bodyweight. No exceptions.
        Bodyweight exercises (push-ups, pull-ups, lunges, planks, etc.) are always fine as accessories — but unless the session is specifically bodyweight-focused, prioritise the listed equipment for main working sets.
        Maximise variety with what IS available — e.g. with a barbell: deadlifts, front squats, overhead press, bent-over rows, cleans, Romanian deadlifts, hip thrusts, floor press, Pendlay rows — not just back squats repeated.
    RULE
  end

  # Returns true when session notes mention specific equipment or a limited setting
  # (home gym, hotel, etc.) — used to filter warm-up options that reference machines.
  def equipment_limited?
    return false unless @session_notes.present?
    notes_lower = @session_notes.downcase
    notes_lower.include?("home gym") || notes_lower.include?("garage") ||
      notes_lower.include?("hotel") || notes_lower.include?("no equipment") ||
      notes_lower.match?(/\b(dumbbell|barbell|olympic bar|kettlebell|resistance band|bands only)\b/)
  end

  # Parse behavior flags from session_notes (replaces old minor tag behavior)
  def session_notes_flag?(pattern)
    @session_notes.present? && @session_notes.match?(pattern)
  end

  def no_run?
    session_notes_flag?(/\bno[- ]?run(ning|s)?\b/i)
  end

  def no_core?
    session_notes_flag?(/\bno[- ]?(core|abs)\b/i)
  end

  def race_simulation?
    session_notes_flag?(/\brace[- ]?sim(ulation)?\b/i)
  end

  def sport_purity_rule
    rules = []

    if no_run?
      rules << "- Do NOT include any running in this session. Replace any running segments with rowing, SkiErg, bike erg, or other non-running cardio."
    end

    if @activity_slug.in?(BODYWEIGHT_ONLY_SLUGS)
      rules << "- BODYWEIGHT ONLY — this program uses NO equipment whatsoever (no barbells, no dumbbells, no kettlebells, no machines, no cardio equipment). Every exercise must use bodyweight only. Ignore the athlete's strength benchmarks for loading — use bodyweight progressions (pistol squats, archer push-ups, pull-up variations, plyometrics) to adjust difficulty instead."
    end

    rules.join("\n").presence
  end

  def core_section_rule
    # Explicit no-core in session notes always wins
    return "- Do NOT include a dedicated core or abs section in this session." if no_core?
    return "- Do NOT include a dedicated core or abs section — this is a short session, keep it focused on the main work." if @duration_mins < 30

    if rand < 0.67
      # Explicitly forbid it ~2/3 of the time — silence is not enough, the LLM adds core by default
      return "- DO NOT include a dedicated core or abs section in this session. No plank circuits, no sit-up blocks, no ab finishers."
    end

    core_mins = @duration_mins >= 45 ? 10 : 5
    "- Core section: include a #{core_mins}-minute dedicated core section (format: straight or rounds) placed towards the end of the session, before the cool-down. Use 3–5 exercises targeting abs and trunk stability (e.g. plank, hollow hold, dead bugs, Russian twist, V-ups, ab wheel rollout, GHD sit-ups, toes-to-bar, L-sit). Be specific with reps or hold times."
  end

  # Randomly selects a Continuous Circuit duration/exercise-count for FM sessions.
  # Ruby picks so the LLM can't default to 12 min every time.
  FM_CONTINUOUS_CIRCUIT_OPTIONS = [
    { exercises: 2, rounds: 4, mins: 8  },
    { exercises: 3, rounds: 3, mins: 9  },
    { exercises: 3, rounds: 4, mins: 12 },
    { exercises: 4, rounds: 3, mins: 12 },
    { exercises: 3, rounds: 5, mins: 15 },
    { exercises: 5, rounds: 3, mins: 15 },
    { exercises: 3, rounds: 6, mins: 18 },
    { exercises: 4, rounds: 5, mins: 20 }
  ].freeze

  def fm_continuous_circuit_config
    opt = FM_CONTINUOUS_CIRCUIT_OPTIONS.sample
    "duration_mins: #{opt[:mins]}, exactly #{opt[:exercises]} exercises (#{opt[:exercises]} exercises × #{opt[:rounds]} rounds = #{opt[:mins]} min)"
  end

  # Randomly selects a session archetype for Functional Muscle so the LLM gets
  # a concrete structural directive rather than being asked to "vary" on its own.
  # Tabata frequency distribution: 40% = 1, 40% = 2, 15% = 3, 5% = 4.
  def fm_session_archetype
    return nil unless @activity_slug == "functional-muscle"

    roll = rand(100)
    tabata_count = case roll
    when  0..39 then 1
    when 40..79 then 2
    when 80..94 then 3
    else             4
    end

    archetypes = {
      1 => [
        "BEAR & LADDER — Generate EXACTLY: Bear Mountain + 10-1 Ladder + 1 tabata. Total: 28 min. STOP. Do not add a continuous circuit or any other block.",
        "MACHINE DAY — Generate EXACTLY: Continuous Circuit + Cardio Intervals + 1 tabata. Total: ~26 min. STOP. No ladder, no Bear Mountain.",
        "LADDER & CIRCUIT — Generate EXACTLY: 10-1 Ladder + Continuous Circuit + 1 tabata. Total: ~28 min. STOP. No Bear Mountain."
      ],
      2 => [
        "CIRCUIT & TABATAS — Generate EXACTLY: Continuous Circuit + 2 tabatas. Total: ~24 min. STOP. No ladder, no Bear Mountain.",
        "BEAR & TABATAS — Generate EXACTLY: Bear Mountain + 2 tabatas. Total: 22 min. STOP. No ladder, no continuous circuit.",
        "LADDER & TABATAS — Generate EXACTLY: 10-1 Ladder + 2 tabatas. Total: 24 min. STOP. No Bear Mountain, no continuous circuit.",
        "LADDER & CIRCUIT & TABATAS — Generate EXACTLY: 10-1 Ladder + Continuous Circuit + 2 tabatas. Total: ~28 min. STOP. No Bear Mountain."
      ],
      3 => [
        "LADDER & 3 TABATAS — Generate EXACTLY: 10-1 Ladder + 3 tabatas. Total: 30 min. STOP. No Bear Mountain, no continuous circuit.",
        "TRIPLE BURN — Generate EXACTLY: Continuous Circuit + 3 tabatas. Total: ~28 min. STOP. No ladder, no Bear Mountain.",
        "DEATH RACE & 3 TABATAS — Generate EXACTLY: Death Race + 3 tabatas. Total: 26 min. STOP. No ladder, no Bear Mountain."
      ],
      4 => [
        "TABATA HEAVY — Generate EXACTLY: 4 tabatas + 1 small block (death race OR every-2-min EMOM). Total: ~30 min. STOP. No ladder, no Bear Mountain, no continuous circuit."
      ]
    }

    "- SESSION SHAPE FOR THIS WORKOUT: #{archetypes[tabata_count].sample} Follow this shape while still obeying the full Functional Muscle rules below."
  end

  # Hard rules specific to Functional Muscle sessions.
  def functional_muscle_rule
    return nil unless @activity_slug == "functional-muscle"

    cc = fm_continuous_circuit_config

    <<~RULE.strip
      - FUNCTIONAL MUSCLE — IGNORE ALL GENERAL WORKOUT DESIGN INSTINCTS. This is a specific class format. Follow this SESSION ORDER exactly — do not rearrange it:

      *** CONTINUOUS CIRCUIT DURATION FOR THIS SESSION (pre-determined — do not change): #{cc} ***

      WEIGHTS: These are high-intensity metabolic sessions. Keep weights light and sustainable. Tabata/metabolic compound exercises: 8–12kg dumbbells, 12–16kg kettlebells. Bear Mountain barbell: 20–30kg only. Strength sets (5×10): sensible working weight — e.g. 40–60kg leg press, 20–30kg shoulder press, 15–25kg side raises. Do NOT prescribe heavy barbell weights (40kg+) for tabata or metabolic blocks. Do NOT prescribe 60kg+ for any strength section.

      SECTION NAMES: Give every section a short, punchy name — NEVER prefix with "Block 1:", "Block 2:", or any number. Numeric prefixes are banned. Tabatas: use fun creative names like "The Burner", "Sweat & Twist", "Ignition", "The Grind", "Pulse Raiser", "Chaos Round" — never "Tabata 1" or the exercise name. Metabolic blocks: use evocative names like "The Grind Loop", "Cardio Blitz", "The Ladder". Strength: "Upper Body Strength", "Lower Body Strength". The section name must accurately describe what's in it — don't call it "Abs Finisher" if the exercise is plate serves or bicep curls; call it "Functional Finisher" or "The Hundred" instead. Only use "Abs Finisher" or "Core 100" when the exercises are actual abs movements.

      1. WARM-UP (always first): format: straight, duration_mins: 5. ONE exercise only — a single cardio machine (assault bike, rower, or ski erg) at easy pace. No mobility, no activation, no circuits. One machine, 5 mins.

      2. METABOLIC BLOCKS (always before strength): Build the metabolic section according to the SESSION SHAPE given above — it tells you exactly how many tabatas to include. Do not add extra tabatas beyond the count specified.

        TIME BUDGET — fixed sections consume half the session. You MUST stay within the metabolic budget or the session will run over. Calculate carefully:
          Fixed sections: Warm-up 5 min + Upper Body Strength 8 min + Lower Body Strength 8 min + Abs 5 min + Cool-down 4 min = 30 min
          Remaining for ALL metabolic blocks combined (including tabatas): #{@duration_mins - 30} min
          Each tabata = 4 min. Add up your chosen blocks — total must not exceed #{@duration_mins - 30} min.

        Block time estimates — use these to budget:
          Tabata [H]: 6 min (4 min work + transitions)
          Bear Mountain [I]: 10 min
          10-1 Ladder [C]: 12 min
          Continuous Circuit [A]: duration_mins as specified above
          Cardio Intervals [D]: 10 min (5 rounds × 2 min)
          Every-2-min EMOM [E]: 10 min
          Death Race [G]: 8 min
          Interval Circuit [B]: 10 min (5 rounds × 2 min)
          20-20 Block [F]: 20 min — only suitable for longer sessions (75+ min)

        - OTHER BLOCKS: Choose from [A]–[I] below to fill the session within the time budget. Do NOT always use the continuous circuit block — it should appear in roughly half of sessions at most.

        [A] CONTINUOUS CIRCUIT — format: emom, emom_style: rotating, #{cc}. One cardio machine (ski/row/bike) + one KB or barbell movement per exercise slot + optionally one abs or bodyweight movement. NO reps, calories, distance, or duration on any exercise — each fills its full minute. Coaching notes only. Do NOT label exercises with minute numbers.

        [B] INTERVAL CIRCUIT — format: rounds, rounds: 5. 2–3 exercises performed every 2 minutes (add this to section notes). Include specific reps and weights. E.g. 20 KB swings + 10 slams + 5 thrusters.

        [C] 10-1 LADDER — format: ladder, start: 10, end: 1, step: 1. ALWAYS exactly 3 exercises from contrasting movement patterns (push + pull + legs, or swing + slam + squat etc). VARY the exercises every session — do NOT default to KB Swings / Wall Balls / Box Jumps. Draw from this pool: KB Swings, Goblet Squats, KB Clean and Press, Thrusters, Upright Rows, Bent Over Rows, Renegade Rows, Burpees, Box Jumps, Step-ups, Jump Squats, Slam Ball, Push Press, Devil Press, DB Lunges, Plate Good Mornings, KB Deadlifts, Pull-ups, Ring Rows, Dips, Push-ups. Pick 3 that contrast (one cardio/plyometric, one push, one pull or hinge).

        [D] CARDIO INTERVALS — format: rounds, rounds: 5. 1 min hard / 1 min rest on a single machine. Ski (target 10 cal/min), Row (target 200m/min), Bike (10–15 cal).

        [E] EVERY-2-MIN EMOM — format: emom, emom_style: circuit, duration_mins: 10. ALWAYS exactly 3 exercises done together at the start of every 2-minute window, rest for remainder. Reps are always multiples of 5. MINIMUM 25 total reps across all 3 exercises — never use 5/5/5 or any combination that totals less than 25. Use varied rep schemes: 15/10/5 (descending), 5/10/20 (ascending), 10/10/10 (even), 10/15/5. Total work per round should take 45–60 seconds leaving 60–75 seconds rest. E.g. 5 clean and press + 10 KB swings + 15 box jumps every 2 mins. Or: 10 thrusters + 10 burpees + 20 sit-ups every 2 mins.

        [F] 20-20 BLOCK — format: rounds, rounds: 10. Every 2 mins: 20 cal cardio + 20 reps of a punchy movement (KB swings, slams, jump squats). 20-minute total block. Only use for 75+ min sessions.

        [G] DEATH RACE — format: rounds, rounds: 5. 10–15 cal bike + 10 burpees. All out.

        [H] TABATA — Use 2 exercises per tabata (ABABABAB = 4 rounds each) — this is the standard format. Standard tabatas: EVERY exercise MUST be a compound (two movements fused into one flowing rep, name must contain "and", "with", "to", or "+"). Each tabata gets DIFFERENT compound pairs — never repeat the same compound in one session. You are encouraged to INVENT new combinations — the goal is creative, flowing pairings that contrast muscle groups. Some examples to spark ideas (don't just copy these): "Squat Curl and Press", "KB Swing with Side Lunge", "Wood Chop with Reverse Lunge", "Bent Over Row to Deadlift", "Side Lunge and Lateral Raise", "Lunge and Overhead Tricep Extension", "Hop onto Box and Bicep Curl", "Clean and Lateral Lunge", "Squat Jump and Shoulder Press", "Plate Halo and Twist", "Push Up to T-Rotation", "Renegade Row to Deadlift", "Reverse Lunge and High Pull", "Squat and Rainbow Press", "Gorilla Row and Jump Squat", "Devil Press and Box Step", "KB Clean and Pivot Press", "Bent Over Row and Clean and Press". CARDIO MACHINE TABATA (use occasionally — at most once per session): one of the two exercises may be a cardio machine (Assault Bike, Rowing Machine, or Ski Erg) — pair it with a compound movement. Example pairings: Assault Bike + Squat Curl and Press, Rowing Machine + Wood Chop with Reverse Lunge, Ski Erg + KB Swing with Side Lunge. Do NOT set reps or calories on the machine exercise — it's a 20s burst, the interval is the constraint. Single compound movements alone (burpees, KB swings, mountain climbers without a second movement) are never acceptable.

        [I] BEAR MOUNTAIN — format: mountain, start: 1, peak: 5, end: 1, step: 1 (1-2-3-4-5-4-3-2-1 reps = 25 bears total). One exercise only: "Bear" (clean → press → front squat → press → back squat = 1 rep). Use a moderate barbell weight (20–30kg). Rest as needed between rungs. Takes approximately 10 minutes.

      3. UPPER BODY STRENGTH (after all metabolic blocks): MANDATORY — must be present in every session. ONE section only, named "Upper Body Strength". format: rounds, rounds: 5, rest_secs: 60, reps: 10. Exactly ONE exercise — pick one at random from this list each time: Low Row, Lat Pulldown, Bench Press, Shoulder Press, Chest Fly, Reverse Fly, Side Raises, Front Raises. Do NOT default to Lat Pulldown or Shoulder Press — every option is equally valid. One exercise, 5 rounds, 10 reps. Nothing else.

      4. LOWER BODY STRENGTH (after upper body): MANDATORY — must be present in every session. ONE section only, named "Lower Body Strength". format: rounds, rounds: 5, rest_secs: 60, reps: 10. Exactly ONE exercise — pick one at random from this list each time: Leg Press, Leg Extension, Leg Curl, Calf Raise, Squats, Deadlifts, Lunges. Do NOT default to Leg Press — every option is equally valid. One exercise, 5 rounds, 10 reps. Nothing else.

      5. ABS / PILATES 100 (after strength, always just before the cool-down): MANDATORY in 90% of sessions — only skip if the metabolic blocks already had heavy abs work throughout. Always 100 reps total, ~5 minutes. Choose ONE of these formats each time (vary across sessions):
        - format: hundred — 100 reps of a single non-abs pilates-style exercise (wall ball slams, bicep curls light, lateral raises light, plate serves). Do not use sit-ups or crunches here. Name the section after the exercise: "The Hundred" or a creative name like "Functional Finisher", "Shoulder Burn", "Plate Party" — NOT "Abs Finisher" (these aren't abs exercises).
        - format: straight — 4–5 abs exercises, each 20–25 reps, one pass through (total = ~100 reps). Name the section "Abs Finisher" or "Core 100" (these ARE abs exercises).
        - format: rounds, rounds: 5 — a single abs exercise × 20 reps per round, or rounds: 4 × 25 reps, or rounds: 2 × 50 reps.
        ABS EXERCISE MENU (pick from this list — mix them up across sessions, never repeat the same combination):
        Sit-ups, Crunches, Overhead crunches, Leg raises, Alternating toe touches, V-ups, Bicycle crunches, Russian twists, Flutter kicks, Hollow holds (timed), Dead bugs, Plank shoulder taps, Mountain climbers (slow), Side plank dips.
        Choose exercises that contrast what was already hit in the metabolic blocks. If the session had lots of KB swings and hip work, lean towards upper-abs and rotation. If it was push-heavy, choose leg raises and lower-abs work.

      6. COOL-DOWN (always last): format: straight, duration_mins: 5. Simple stretch, 2–3 holds only.

      BANNED in Functional Muscle: activation blocks, mobility warm-up sequences, AMRAP, single sets of any weighted exercise, any rep scheme other than 5×10 or 5×5 for the strength sections, reps on 12-min rotating EMOM exercises, powerlifting-style main sets.
    RULE
  end

  # When the session is an event-type (Hyrox/Deka) but NOT a race simulation,
  # tell the LLM to use 50–65% of competition rep counts in multi-round training sets.
  def training_rep_rule
    return nil unless event_session?
    return nil if race_simulation?

    main_slug = @activity_slug || ""

    case main_slug
    when "deka", "deka-fit", "deka-strong", "deka-mile"
      <<~RULE.strip
        - TRAINING REP COUNTS (Deka): When using Deka zone movements in multi-round sets (rounds ≥ 2), use 50–65% of competition reps — NOT full race amounts. Race = training reference only. Examples:
            * RAM Reverse Lunges: race 30 reps → training 15–20/round
            * Box Jump / Step Over: race 20 reps → training 10–13/round
            * Med Ball Sit-up Throw: race 25 reps → training 12–16/round
            * Air Bike: race 25 cal → training 12–16 cal/round
            * Dead Ball Yoke Over: race 20 reps → training 10–13/round
            * RAM Weighted Burpees: race 20 reps → training 10–13/round
          Distance zones (Row 500m, SkiErg 500m, Sled, Farmer's Carry) may keep full or reduced distance depending on session focus.
      RULE
    when "deka-atlas"
      <<~RULE.strip
        - TRAINING REP COUNTS (Deka Atlas): When using Deka Atlas movements in multi-round sets (rounds ≥ 2), use 50–65% of competition reps. All stations are 20 reps at competition (except Jump Rope = 100). Training: 10–13 reps/round for 20-rep stations; 50–65 reps/round for Jump Rope.
      RULE
    when "hyrox"
      <<~RULE.strip
        - MANDATORY RUNNING (Hyrox): Every Hyrox session MUST include running intervals. The race is 8×1km runs — running is the backbone. Include 1km repeats, 800m intervals, or run-to-station transitions. Running must appear in the main set, not just the warm-up.
        - TRAINING REP COUNTS (Hyrox): When using Hyrox stations in multi-round sets (rounds ≥ 2), use reduced training volumes — NOT full race amounts. Examples:
            * Wall Balls: race 100 reps → training 40–65/round
            * Sandbag Lunges: race 100m → training 40–65m/round
            * Farmers Carry: race 200m → training 50–80m/round
            * Sled: reduce load to 60–70% of competition weight
          Do NOT prescribe a full 1km SkiErg or Row as part of a multi-round circuit — reserve that for single-effort time trials.
      RULE
    end
  end

  # When the "race-simulation" or "race-sim" minor tag is present, override the session
  # with a full competition run-through at exact race weights/distances/reps in race order.
  def race_simulation_rule
    return nil unless race_simulation?

    main_slug = @activity_slug || ""

    case main_slug
    when "deka", "deka-fit"
      <<~RULE.strip
        - RACE SIMULATION MODE (Deka Fit): Generate an exact Deka Fit event run-through. Use ALL 10 zones in official race order with full competition specs. Format each zone as its own for_time section. No warm-up or cool-down — this is a competition-day simulation. Zone order:
            1. RAM Reverse Lunges: 30 reps (15/leg) | 25kg (M) / 15kg (F)
            2. Row: 500m
            3. Box Jump / Step Over: 20 reps | 24" box
            4. Med Ball Sit-up Throw: 25 reps | 9kg (M) / 6.5kg (F)
            5. SkiErg: 500m
            6. Farmer's Carry: 100m | 27kg each hand (M) / 18kg (F)
            7. Air Bike: 25 calories
            8. Dead Ball Yoke Over: 20 reps (10/side) | 27kg (M) / 18kg (F)
            9. Sled Push / Pull: 100m (push 10m + pull 10m × 5)
            10. RAM Weighted Burpees: 20 reps | 20kg (M) / 10kg (F)
          Between each zone athletes transition themselves — model this as a single workout with 10 for_time sections, one per zone.
      RULE
    when "deka-strong"
      <<~RULE.strip
        - RACE SIMULATION MODE (Deka Strong): Generate an exact Deka Strong event run-through. Same 10 zones as Deka Fit but with heavier loads and different distances. Use official Deka Strong competition specs for weights/distances in race order. Format each zone as its own for_time section. No warm-up/cool-down.
      RULE
    when "deka-atlas"
      <<~RULE.strip
        - RACE SIMULATION MODE (Deka Atlas): Generate an exact Deka Atlas event run-through. Use ALL 10 stations in official race order with full competition specs. Format each station as its own for_time section. No warm-up/cool-down. Station order:
            1. Barbell Thrusters: 20 reps | 45kg (M) / 30kg (F)
            2. Bar-Facing Burpees Over Bar: 20 reps
            3. Surrender Lunges (weighted): 20 reps | 22.5kg (M) / 15kg (F)
            4. Single Arm DB Ground to Overhead (alternating): 20 reps | 22.5kg (M) / 15kg (F)
            5. Dumbbell Bear Crawl: 40m | 22.5kg (M) / 15kg (F)
            6. Weighted Sit-ups: 20 reps | 15kg (M) / 9kg (F)
            7. Farmer's Carry: 60m | 45kg each hand (M) / 32kg each hand (F)
            8. DB Shoulder to Overhead Press: 20 reps | 22.5kg (M) / 15kg (F)
            9. Jump Rope Single Unders: 100 reps
            10. Atlas Shoulder to Carry: 100m | 45kg (M) / 32kg (F)
      RULE
    when "hyrox"
      <<~RULE.strip
        - RACE SIMULATION MODE (Hyrox): Generate an exact Hyrox event run-through. Structure: 8 × (1km run → 1 functional station). Model each run and each station as its own for_time section. Use full competition specs. Station order:
            1. 1km run → SkiErg 1000m
            2. 1km run → Sled Push 50m | Open: 152kg (M) / 102kg (F) | Pro: 202kg (M) / 152kg (F)
            3. 1km run → Sled Pull 50m | Open: 103kg (M) / 78kg (F) | Pro: 153kg (M) / 103kg (F)
            4. 1km run → Burpee Broad Jumps 80m
            5. 1km run → Rowing 1000m
            6. 1km run → Farmers Carry 200m | Open: 2×24kg (M) / 2×16kg (F) | Pro: 2×32kg (M) / 2×24kg (F)
            7. 1km run → Sandbag Lunges 100m | Open: 20kg (M) / 10kg (F) | Pro: 30kg (M) / 20kg (F)
            8. 1km run → Wall Balls 100 reps | Open: 6kg to 10ft (M) / 4kg to 9ft (F) | Pro: 9kg to 10ft (M) / 6kg to 9ft (F)
          No warm-up/cool-down — this is a competition-day simulation.
      RULE
    else
      "- RACE SIMULATION MODE: Generate a full event run-through for #{@activity} using competition-accurate reps, distances, and weights in race order. Format as for_time sections. No warm-up/cool-down."
    end
  end

  def build_session_structure
    if @duration_mins < 30
      return "- Session structure: Warm-up (3 min) → 1 main set → Cool-down (2 min). " \
             "This is a short session — keep it tight. No finisher. 1 main set only. " \
             "Do NOT set duration_mins on the main set."
    end

    # Base of 1 main set for 30 min, +1 set per additional 15 min
    # e.g. 30→1, 45→2, 60→3, 75→4
    main_sets = [ 1 + ((@duration_mins - 30) / 15.0).floor, 1 ].max

    set_word = main_sets == 1 ? "1 main set" : "#{main_sets} main sets"

    "- Session structure: Warm-up (5 min) → #{set_word} → Finisher → Cool-down (5 min). " \
    "The rule is: 30 min = 1 main set, then add 1 more set for every additional 15 minutes (45 min = 2 sets, 60 min = 3 sets, 75 min = 4 sets). " \
    "The Finisher is always present — a short punchy section (Tabata = 4 min, or a for_time sprint). " \
    "DO NOT add more main sets than #{main_sets} — rest and transitions between exercises fill the remaining time naturally. " \
    "Do NOT set duration_mins on main sets or try to make section durations add up to #{@duration_mins}."
  end

  def build_remix_prompt
    source_json = {
      activity:      @source_workout.activity_name,
      duration_mins: @source_workout.duration_mins,
      difficulty:    @source_workout.difficulty,
      structure:     @source_workout.structure
    }.to_json

    <<~PROMPT.strip
      You are a personal trainer specialising in writing fun workouts that athletes enjoy and improves their fitness.

      If the user is doing a run, don't add any gym exercises, just use running and dynamic stretches.

      Generate a #{@duration_mins}-minute #{@difficulty} workout inspired by this existing workout:
      #{source_json}

      Draw on its movement patterns, energy systems, and overall feel — but this must be a genuinely different session. Swap exercises, change rep schemes, restructure sections, or shift the emphasis. Someone who does both workouts back-to-back should feel like they trained differently.
      #{@session_notes.present? ? "\n      *** ATHLETE'S SESSION FOCUS (HIGHEST PRIORITY): \"#{@session_notes}\" — The exercises you select MUST clearly reflect this focus. The remixed workout must maintain this same focus — if the original was sled-heavy, the remix must also be sled-heavy with different exercises/formats. ***\n" : ""}
      Use the create_workout tool. Requirements:
      - Total duration close to #{@duration_mins} minutes
      - Same training focus as the source but a clearly distinct session
      - Be specific with reps, distances, and weights
      - Do not include a workout_type field
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
    if @user.pool_length.present?
      sections << "Training environment: #{@user.pool_length} pool."
    end

    benchmarks = format_benchmarks
    sections << benchmarks if benchmarks.present?

    known_weights = format_known_weights
    sections << known_weights if known_weights.present?

    return nil if sections.empty?

    "## Athlete Context\n#{sections.join("\n")}\n"
  end

  # Formats the user's saved exercise weights as a coaching hint.
  def format_known_weights
    weights = @user.exercise_weights.presence
    return nil unless weights.is_a?(Hash) && weights.any?

    lines = weights.map do |key, kg|
      name = key.to_s.gsub("_", " ").split.map(&:capitalize).join(" ")
      "  - #{name}: #{kg}kg"
    end.sort

    "Known working weights (use these as the starting point — adjust slightly for intensity or format):\n#{lines.join("\n")}"
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

  # Pre-computes actual training weights at common rep ranges from 1RM values.
  # Returns a formatted string with per-lift, per-rep-range weights so the LLM
  # never has to calculate percentages — it can just read the target kg directly.
  def build_strength_weight_guide(pbs, bw)
    lines = []

    # 1RM → training weight at standard rep ranges (Epley approximation)
    # 3-5 reps=87% | 6-8 reps=80% | 10 reps=75% | 15 reps=68% | 20+ reps=62%
    lift_map = {
      "deadlift_1rm"   => "Deadlift / Trap Bar Deadlift / RDL / Sumo Deadlift",
      "squat_1rm"      => "Back Squat / Front Squat / Bulgarian Split Squat",
      "bench_1rm"      => "Bench Press / Incline Press / DB Press / Push Press",
      "clean_jerk_1rm" => "Clean & Jerk / Power Clean / Hang Clean / Hang Power Clean",
      "snatch_1rm"     => "Snatch / Hang Snatch / Power Snatch"
    }

    lift_map.each do |key, label|
      next unless pbs[key]
      rm = pbs[key].to_f
      lines << "  #{label} (1RM #{rm.round}kg): " \
               "3–5 reps=#{(rm * 0.87).round}kg | " \
               "6–8 reps=#{(rm * 0.80).round}kg | " \
               "10 reps=#{(rm * 0.75).round}kg | " \
               "15 reps=#{(rm * 0.68).round}kg | " \
               "20+ reps=#{(rm * 0.62).round}kg — NEVER exceed the 1RM of #{rm.round}kg"
    end

    # Derive carry / unilateral loads from deadlift 1RM if available
    if pbs["deadlift_1rm"]
      dl = pbs["deadlift_1rm"].to_f
      fc_lo = (dl * 0.30).round
      fc_hi = (dl * 0.40).round
      sb_lo = (bw * 0.50).round
      sb_hi = (bw * 0.75).round
      lines << "  Farmer's Carry: #{fc_lo}–#{fc_hi}kg per hand (30–40% of deadlift 1RM)"
      lines << "  Sandbag / Yoke / Atlas stone: #{sb_lo}–#{sb_hi}kg (50–75% body weight)" if bw > 0
    end

    lines << "  Body weight: #{bw.round(1)}kg" if bw > 0
    lines << "  CRITICAL: These are absolute maximums — the athlete cannot lift more than their 1RM. " \
             "Scale all prescribed weights to the values above. A 120kg deadlift 1RM means 0 reps at 180kg."

    lines.join("\n")
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

    # ── Strength PBs — detect presence for the output block ─────────────────
    %w[bench_1rm squat_1rm deadlift_1rm clean_jerk_1rm snatch_1rm].each do |key|
      has_strength = true if pbs[key]
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
    return nil if cardio_lines.empty? && !has_strength && other_pb_lines.empty? && bw.zero?

    out = []

    if has_cardio
      out << "Cardio pace guide (use these exact paces — do not invent times outside these ranges):\n" \
             "#{cardio_lines.map { |l| "  - #{l}" }.join("\n")}"
    end

    if has_strength || bw > 0
      strength_guide = build_strength_weight_guide(pbs, bw)
      out << "Strength weight guide — HARD LIMITS, do not exceed these:\n#{strength_guide}"
    end

    unless other_pb_lines.empty?
      out << "Other PBs:\n#{other_pb_lines.map { |l| "  - #{l}" }.join("\n")}"
    end

    out.join("\n")
  end

  # Returns true when the main tag is an event type with a fixed station/zone list.
  def event_session?
    EVENT_STATIONS.key?(@activity_slug || "")
  end

  # Builds a compact reference block listing only the selected stations with their
  # race-accurate weights/distances. Replaces the full station table from the context
  # file so the LLM can't use the table as a checklist of "things to include".
  def build_station_reference(stations)
    ref_map = EVENT_REFERENCE[@activity_slug || ""] || {}
    lines = stations.filter_map do |s|
      ref = ref_map[s]
      next nil unless ref
      text = resolve_station_ref(ref)
      "  #{s}: #{text}"
    end
    return nil if lines.empty?
    "Race-accurate reference for this session's stations (weights / distances):\n#{lines.join("\n")}"
  end

  # If the reference is a Hash with peak/foundation keys, select based on difficulty.
  # Advanced = peak weights, beginner = foundation, intermediate = both shown.
  def resolve_station_ref(ref)
    return ref unless ref.is_a?(Hash)

    case @difficulty
    when "advanced"
      "#{ref[:peak]} (Peak)"
    when "beginner"
      "#{ref[:foundation]} (Foundation)"
    else
      "Peak: #{ref[:peak]} | Foundation: #{ref[:foundation]} — use a weight between the two"
    end
  end

  # Activity slugs that are inherently bodyweight-only programs.
  BODYWEIGHT_ONLY_SLUGS = %w[bodyweight meta-fit metafit metafit-bodyweight].freeze

  # Randomly selects a subset of event stations for this session.
  # Returns nil if the event has no station pool, or if the user specified actual
  # focus movements as minor tags (in which case the LLM uses those freely).
  # Meta-instruction tags (no-run etc.) are ignored for this check.
  def pick_event_stations
    pool = EVENT_STATIONS[@activity_slug || ""]
    return nil if pool.nil?

    count = STATION_COUNT_WEIGHTS.sample
    pool.shuffle.first(count)
  end

  def fmt_secs(secs)
    m = secs / 60
    s = secs % 60
    "#{m}:#{s.to_s.rjust(2, "0")}"
  end

  # Loads sport-specific context files based on the workout's tags.
  # Deduplicates — if multiple tags map to the same file, it's only included once.
  def load_sport_context(tag_names)
    files_to_load = tag_names.flat_map do |name|
      Array(CONTEXT_TAG_MAP[name.downcase.parameterize])
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

  def validate_and_fix(workout_data)
    validator = WorkoutValidator.new(workout_data, difficulty: @difficulty, duration_mins: @duration_mins, main_tag_slug: @activity_slug || "")
    result    = validator.validate_and_fix
    validator.fixes.each    { |msg| Rails.logger.info("[WorkoutValidator] Fixed: #{msg}") }
    validator.warnings.each { |msg| Rails.logger.warn("[WorkoutValidator] Warn:  #{msg}") }
    result
  end

  # Returns true when the main tag has pre-written context or is a known event.
  def known_program?
    slug = @activity_slug || ""
    CONTEXT_TAG_MAP.key?(slug) || EVENT_STATIONS.key?(slug)
  end

  # Fires a fast research call if the main tag is an unknown program/style.
  # Returns a hash of structured program info, or nil if not applicable / on error.
  def research_unknown_program
    return nil if @activity.nil?
    return nil if known_program?

    research_program(@activity)
  rescue => e
    Rails.logger.warn("WorkoutLLMGenerator: research pass failed for '#{@activity}': #{e.message}")
    nil
  end

  # Makes a fast, cheap LLM call to look up a fitness program by name.
  # Results are cached in Solid Cache (DB-backed) for 7 days — program descriptions
  # don't change, so re-researching every generation is wasteful.
  def research_program(program_name)
    cache_key = "workout_llm_research_#{program_name.parameterize}"
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    prompt = <<~PROMPT
      You are an expert fitness coach with deep knowledge of group fitness programs, gym classes, and training methodologies.

      Describe the training program or class style called "#{program_name}" in enough detail that a personal trainer could accurately recreate a genuine session.

      Focus on:
      - The exact flow and structure of a typical session (phases, blocks, timing)
      - What the cardio component looks like — equipment, intervals, intensity
      - What the strength/floor work looks like — movements, rep ranges, loading, circuit style
      - Specific exercises with example prescriptions (reps, weight, duration)
      - What makes it feel distinctively like "#{program_name}" and not just a generic gym class

      ACCURACY IS CRITICAL — be precise and honest:
      - Only include equipment that is genuinely used in this specific program. If it is bodyweight-only, say so and do not list gym equipment.
      - Do not pad the exercise list with generic movements that aren't characteristic of this program.
      - If you are uncertain about something, be conservative rather than guessing.

      Use the describe_fitness_program tool to return your answer.
    PROMPT

    result = call_llm(prompt, tools: [ RESEARCH_TOOL_DEFINITION ], tool_choice: { type: "any" }, max_tokens: 1500)
    Rails.cache.write(cache_key, result, expires_in: 7.days) if result.present?
    result
  end

  # Formats the research result into a prompt section.
  def build_program_research_context(research)
    return nil if research.blank?
    return nil if research["skipped"].present?

    lines = []
    lines << "## Program Context: #{@activity}"
    lines << research["description"] if research["description"].present?

    if research["session_structure"].present?
      lines << "\n**Session structure — FOLLOW THIS FLOW:**"
      lines << research["session_structure"]
    end

    if research["cardio_style"].present?
      lines << "\n**Cardio component:** #{research["cardio_style"]}"
    end

    if research["strength_style"].present?
      lines << "\n**Strength/floor component:** #{research["strength_style"]}"
    end

    if Array(research["equipment"]).any?
      lines << "\n**Equipment:** #{research["equipment"].join(", ")}"
    end

    if Array(research["typical_exercises"]).any?
      lines << "\n**Exercises from this program (use these — do not substitute generic gym movements):**"
      Array(research["typical_exercises"]).each { |ex| lines << "  - #{ex}" }
    end

    if Array(research["signature_characteristics"]).any?
      lines << "\n**What makes it feel like #{@activity}:**"
      Array(research["signature_characteristics"]).each { |c| lines << "  - #{c}" }
    end

    lines << "\nThe session MUST feel authentically like #{@activity}. Follow the structure and use the exercises above — someone who has attended a real class should recognise it immediately."

    lines.join("\n")
  end

  def call_llm(prompt, tools: [ TOOL_DEFINITION ], tool_choice: { type: "any" }, max_tokens: 4096)
    @llm_calls ||= []
    api_key = ENV.fetch("ANTHROPIC_API_KEY") { raise WorkoutGenerationError, "ANTHROPIC_API_KEY not configured" }

    body = {
      model:       MODEL,
      max_tokens:  max_tokens,
      tools:       tools,
      tool_choice: tool_choice,
      messages:    [ { role: "user", content: prompt } ]
    }

    http              = Net::HTTP.new(API_URI.host, API_URI.port)
    http.use_ssl      = true
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Post.new(API_URI.path)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = api_key
    request["anthropic-version"] = "2023-06-01"
    request.body = body.to_json

    retries = 0
    begin
      response = http.request(request)
      unless response.code.to_i == 200
        case response.code.to_i
        when 529, 503
          raise WorkoutGenerationError, :overloaded
        when 429
          raise WorkoutGenerationError, :rate_limited
        when 500, 502
          raise WorkoutGenerationError, :server_error
        else
          raise WorkoutGenerationError, "Failed to generate workout (error #{response.code}). Please try again."
        end
      end
    rescue WorkoutGenerationError => e
      if e.message.to_sym.in?(%i[overloaded rate_limited server_error]) && retries < 5
        # 5, 10, 20, 30, 30 seconds — Anthropic outages typically clear within a minute
        wait = [ 5 * (2 ** retries), 30 ].min
        Rails.logger.warn "LLM call #{e.message} — retry #{retries + 1}/5 after #{wait}s"
        sleep wait
        retries += 1
        retry
      end
      raise WorkoutGenerationError, case e.message.to_sym
      when :overloaded    then "The AI is overloaded right now."
      when :rate_limited  then "Too many requests right now."
      when :server_error  then "The AI service is temporarily unavailable."
      else e.message
      end
    end

    parsed     = JSON.parse(response.body)
    tool_block = parsed["content"].find { |b| b["type"] == "tool_use" }
    raise WorkoutGenerationError, "No workout returned by LLM" unless tool_block

    @llm_calls << { prompt: prompt, response: tool_block["input"] }

    tool_block["input"]
  end

  def create_workout(data)
    activity_name = @activity || @source_workout&.activity_name
    activity_record = activity_name.present? ? Activity.find_or_create_by!(name: activity_name) : nil

    workout = Workout.create!(
      user:          @user,
      name:          data["name"].presence || "Generated Workout",
      activity:      activity_record,
      session_notes: @session_notes,
      duration_mins: data["duration_mins"].to_i.positive? ? data["duration_mins"] : @duration_mins,
      difficulty:    Workout::DIFFICULTIES.include?(data["difficulty"]) ? data["difficulty"] : @difficulty,
      status:        "active",
      structure:     data["structure"]
    )

    # Community tag (e.g. "Hyrox Manchester 2026")
    if @group_tag_name.present?
      tag = Tag.find_or_create_by!(slug: @group_tag_name.parameterize) { |t| t.name = @group_tag_name }
      workout.tags = [ tag ]
    end

    Rails.cache.write("workout_llm_debug_#{workout.id}", @llm_calls, expires_in: 2.hours) if @llm_calls.present?
    DiscoverExerciseVideosJob.perform_later(workout.id)
    workout
  end
end
