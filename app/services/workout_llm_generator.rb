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
    "hyrox"              => "hyrox.md",
    "deka"               => "deka_fit.md",
    "deka-fit"           => "deka_fit.md",
    "deka-strong"        => "deka_strong.md",
    "deka-mile"          => "deka_mile.md",
    "deka-atlas"         => "deka_atlas.md",
    "dirty-dozen"        => "dirty_dozen.md",
    "crossfit"           => "crossfit.md",
    "functional-fitness" => "functional.md",
    "hiit"               => "hiit.md",
    "bodyweight"         => "bodyweight.md",
    "meta-fit"           => "metafit.md",
    "metafit"            => "metafit.md",
    "metafit-bodyweight" => "metafit.md",
    "barry-s-bootcamp"   => "barrys.md",
    "barrys-bootcamp"    => "barrys.md",
    "barrys"             => "barrys.md",
    "f45"                => "f45.md",
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
  ].freeze

  COOLDOWN_OPTIONS = [
    { label: "Lower Body Focus",
      instruction: "Prioritise hips, hamstrings, quads: hip flexor stretch (kneeling lunge, 30s each side), pigeon pose or figure-four glute stretch (45s each side), seated forward fold (45s), standing quad stretch (30s each leg), lying spinal twist (30s each side)." },
    { label: "Upper Body Focus",
      instruction: "Prioritise chest, shoulders, lats: chest opener with hands clasped behind back (30s), cross-body shoulder stretch (30s each arm), doorframe pec stretch (30s each side), thread the needle (30s each side), child's pose with arms extended (45s)." },
    { label: "Full Body Stretch",
      instruction: "Hit everything briefly: hip flexor lunge stretch (30s each side), hamstring forward fold (30s), chest opener (30s), thoracic rotation in quadruped (30s each side), lying glute stretch (30s each side)." },
    { label: "Mobility Flow",
      instruction: "Slow continuous movement rather than held stretches: world's greatest stretch (3 reps each side), deep squat to stand (5 reps), cat-cow (8 reps), thread the needle (3 each side), downward dog pedalling heels (10 reps). Describe movements in notes." },
    { label: "Recovery Stretch",
      instruction: "Longer holds, very relaxed: child's pose (60s), butterfly stretch seated (60s), supine hamstring pull (45s each leg), lying spinal twist (45s each side). Only 4 exercises but held longer — designed to genuinely lower heart rate and relax." },
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
      instruction: "Metabolic session — keep rest short and reps high. Lighter weights, fast transitions, sustained effort. Think: sweat, breathing hard, and muscular fatigue from volume rather than load." },
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
                  format:             { type: "string", enum: %w[straight amrap rounds emom tabata for_time ladder mountain matrix], description: "straight=sets with rest, rounds=multiple rounds of the same set, amrap=as many rounds as possible in a time cap, emom=every minute on the minute, tabata=20s work/10s rest×8, for_time=complete prescribed reps/distance as fast as possible (record finishing time), ladder/mountain=reps/distance change each round, matrix=progressive exercise combination (add then remove exercises each round: A → A+B → A+B+C → B+C → C)" },
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

  def self.call(user:, duration_mins:, difficulty:, main_tag_id: nil, minor_tag_ids: [], group_code_id: nil, tag_ids: [], source_workout: nil, session_notes: nil)
    new(user: user, main_tag_id: main_tag_id, minor_tag_ids: minor_tag_ids, group_code_id: group_code_id, tag_ids: tag_ids, duration_mins: duration_mins, difficulty: difficulty, source_workout: source_workout, session_notes: session_notes).call
  end

  def initialize(user:, duration_mins:, difficulty:, main_tag_id: nil, minor_tag_ids: [], group_code_id: nil, tag_ids: [], source_workout: nil, session_notes: nil)
    @user           = user
    @main_tag       = main_tag_id.present? ? Tag.find_by(id: main_tag_id) : nil
    @minor_tags     = Tag.where(id: Array(minor_tag_ids).map(&:to_i).reject(&:zero?))
    @group_code_tag = group_code_id.present? ? Tag.find_by(id: group_code_id) : nil
    # tag_ids kept for backwards compat (remix path uses source workout tags directly)
    @tag_ids        = tag_ids.any? ? Array(tag_ids).map(&:to_i).reject(&:zero?) : ([@main_tag&.id] + @minor_tags.map(&:id)).compact
    @duration_mins  = duration_mins.to_i
    @difficulty     = difficulty
    @source_workout = source_workout
    @session_notes  = session_notes.presence
  end

  def call
    if @source_workout
      tag_names    = @source_workout.tags.map(&:name)
      prompt       = build_remix_prompt
      workout_data = call_llm(prompt)
      create_workout(workout_data, tag_names)
    else
      context_workouts = fetch_context
      program_research = research_unknown_program
      prompt           = build_prompt(context_workouts, program_research)
      workout_data     = call_llm(prompt)
      workout_data     = validate_and_fix(workout_data)
      workout_data     = collapse_duplicate_exercises(workout_data)
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
      kept = exercises.first.dup
      kept.delete("notes") if kept["notes"].to_s.match?(/\Aset\s*\d+\z/i)
      section["exercises"] = [ kept ]
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
    warmup   = WARMUP_OPTIONS.sample
    cooldown = COOLDOWN_OPTIONS.sample
    <<~WC
      ## Warm-Up Approach: #{warmup[:label]}
      #{warmup[:instruction]}

      ## Cool-Down Approach: #{cooldown[:label]}
      #{cooldown[:instruction]}
    WC
  end

  def build_prompt(context_workouts, program_research = nil)
    main_name  = @main_tag&.name || "general fitness"
    minor_str  = @minor_tags.map(&:name).join(", ")

    selected_stations = pick_event_stations
    station_constraint = if selected_stations
      " Anchor movements for this session (must appear in the main set): #{selected_stations.join(", ")}. Supplement freely with exercises from the #{main_name} training toolkit."
    end

    task_sentence = if minor_str.present?
      "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} session with a focus on: #{minor_str}.#{station_constraint}"
    else
      "Generate a #{@duration_mins}-minute #{@difficulty} #{main_name} session.#{station_constraint}"
    end

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

    if program_research
      sections << build_program_research_context(program_research)
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

    if @session_notes.present?
      sections << <<~NOTES
        ## Athlete's Requests for This Session
        The athlete has provided the following instructions — treat these as hard requirements, not suggestions:
        #{@session_notes}

        Examples of how to interpret requests:
        - Injury mentions (e.g. "injured knee", "bad shoulder") → avoid exercises that load or stress that area; substitute with movements that work around it
        - Equipment constraints (e.g. "dumbbells only", "no barbell") → use only the specified equipment throughout
        - Style preferences (e.g. "heavy lifting", "cardio focus") → weight the session accordingly
      NOTES
    end

    sport_rule      = sport_purity_rule
    core_rule       = core_section_rule
    pace_limits     = pace_limit_rule
    structure_rule  = build_session_structure
    station_rule    = if selected_stations
      "- ANCHOR MOVEMENTS: #{selected_stations.join(", ")} must be central to the main set. Complement them with toolkit exercises from the sport context — create a complete, varied workout, not a drill of the anchor movements repeated in every section."
    end

    sections << <<~RULES
      Use the create_workout tool. Requirements:
      #{structure_rule}
      #{station_rule}
      - Warm-up: always 5 minutes (format: straight, duration_mins: 5). Use the Warm-Up Approach specified above — follow it exactly.
      - Cool-down: always 5 minutes (format: straight, duration_mins: 5). Use the Cool-Down Approach specified above. No reps or distances — hold times only, described in notes (e.g. "30s each side").
      - Main sets: do NOT set duration_mins on main sets — let the reps, rounds, and format define the work. Only amrap and emom sections need a duration_mins (their time cap). A short punchy finisher (e.g. Tabata, for_time sprint) is a welcome extra at the end of the main work.
      #{core_rule}
      - Be specific with reps, distances, and weights
      - Give it a punchy, memorable name — something a gym community would actually call it (CrossFit-style), not a generic description
      #{sport_rule}
      #{pace_limits}
      - FORMAT SELECTION — choose the best format for each section. Actively vary formats across sections (do not use the same format for every section):
        * tabata — high-intensity cardio bursts or bodyweight finishers. 20s on / 10s off × 8 rounds = exactly 4 minutes. Set duration_mins: 4. Great for: assault bike, ski erg, burpees, KB swings, box jumps, jump rope. Do NOT add reps or calories to tabata exercises — the 20s interval is the constraint. You may specify distance_m or weight_kg where relevant.
        * emom — strength, skill work, or paced conditioning. Each minute: do the prescribed reps, rest for the remainder. HARD REP LIMITS — total reps across ALL exercises in one minute: beginner ≤6, intermediate ≤9, advanced ≤12. If using multiple exercises, each equipment transition costs ~10s of that minute, so 2 exercises is usually the max (3 only if all bodyweight and no setup). Examples that WORK: "EMOM 10: 6 thrusters + 4 burpees" | "EMOM 12: 8 KB swings + 4 pull-ups". Examples that DON'T WORK: "EMOM 10: 10 thrusters + 10 pull-ups + 10 squats" (way too much — impossible in 60s). Great for: barbell work, gymnastics, moderate cardio intervals.
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
        * matrix — progressive exercise combinations. List 3–5 exercises in order. The section builds up then strips back: for 3 exercises: A, A+B, A+B+C, B+C, C. For 4: A, A+B, A+B+C, A+B+C+D, B+C+D, C+D, D. For 5: A, A+B, A+B+C, A+B+C+D, A+B+C+D+E, B+C+D+E, C+D+E, D+E, E. IMPORTANT: all exercises must use the same metric — either all reps (same count each) or all duration_s (same seconds each). Prefer duration_s: 30 for each exercise most of the time — this is the most common Metafit style. Set rest_secs for the rest between each combination (typically 30–60s).
      - SINGLE-EXERCISE SECTIONS are valid and often better than circuits, especially for strength and power work. A section with just one exercise is perfectly correct: e.g. '5 × 5 Deadlift (heavy)', 'EMOM 10: 8 Thrusters', '4 × 8 Romanian Deadlift'. Do not feel obligated to bundle every movement into a multi-exercise circuit — for strength sessions in particular, each major lift should usually get its own dedicated section.
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

  # Returns a bullet-point rule for explicit exclusions (e.g. "no-run" minor tag).
  def sport_purity_rule
    rules = []

    minor_slugs = @minor_tags.map(&:slug)
    if minor_slugs.any? { |s| s.in?(%w[no-run no-running no-runs]) }
      rules << "- Do NOT include any running in this session. Replace any running segments with rowing, SkiErg, bike erg, or other non-running cardio."
    end

    if @main_tag&.slug.in?(BODYWEIGHT_ONLY_SLUGS)
      rules << "- BODYWEIGHT ONLY — this program uses NO equipment whatsoever (no barbells, no dumbbells, no kettlebells, no machines, no cardio equipment). Every exercise must use bodyweight only. Ignore the athlete's strength benchmarks for loading — use bodyweight progressions (pistol squats, archer push-ups, pull-up variations, plyometrics) to adjust difficulty instead."
    end

    rules.join("\n").presence
  end

  def core_section_rule
    minor_slugs = @minor_tags.map(&:slug)
    # Explicit no-core tag always wins
    return "- Do NOT include a dedicated core or abs section in this session." if minor_slugs.any? { |s| s.in?(%w[no-core no-abs no-core-work]) }
    return nil if @duration_mins < 20

    if rand < 0.67
      # Explicitly forbid it ~2/3 of the time — silence is not enough, the LLM adds core by default
      return "- DO NOT include a dedicated core or abs section in this session. No plank circuits, no sit-up blocks, no ab finishers."
    end

    core_mins = @duration_mins >= 45 ? 10 : 5
    "- Core section: include a #{core_mins}-minute dedicated core section (format: straight or rounds) placed towards the end of the session, before the cool-down. Use 3–5 exercises targeting abs and trunk stability (e.g. plank, hollow hold, dead bugs, Russian twist, V-ups, ab wheel rollout, GHD sit-ups, toes-to-bar, L-sit). Be specific with reps or hold times."
  end

  def build_session_structure
    # Base of 1 main set for 30 min, +1 set per additional 15 min
    # e.g. 30→1, 45→2, 60→3, 75→4
    main_sets = [1 + ((@duration_mins - 30) / 15.0).floor, 1].max

    set_word = main_sets == 1 ? "1 main set" : "#{main_sets} main sets"

    "- Session structure: Warm-up (5 min) → #{set_word} → Finisher → Cool-down (5 min). " \
    "The rule is: 30 min = 1 main set, then add 1 more set for every additional 15 minutes (45 min = 2 sets, 60 min = 3 sets, 75 min = 4 sets). " \
    "The Finisher is always present — a short punchy section (Tabata = 4 min, or a for_time sprint). " \
    "DO NOT add more main sets than #{main_sets} — rest and transitions between exercises fill the remaining time naturally. " \
    "Do NOT set duration_mins on main sets or try to make section durations add up to #{@duration_mins}."
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
  META_MINOR_SLUGS = %w[no-run no-running no-runs no-core no-abs no-core-work].freeze

  # Main tag slugs that are inherently bodyweight-only programs.
  BODYWEIGHT_ONLY_SLUGS = %w[bodyweight meta-fit metafit metafit-bodyweight].freeze

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
    validator = WorkoutValidator.new(workout_data, difficulty: @difficulty, duration_mins: @duration_mins)
    result    = validator.validate_and_fix
    validator.fixes.each    { |msg| Rails.logger.info("[WorkoutValidator] Fixed: #{msg}") }
    validator.warnings.each { |msg| Rails.logger.warn("[WorkoutValidator] Warn:  #{msg}") }
    result
  end

  # Returns true when the main tag has pre-written context or is a known event.
  def known_program?
    slug = @main_tag&.slug || ""
    CONTEXT_TAG_MAP.key?(slug) || EVENT_STATIONS.key?(slug)
  end

  # Fires a fast research call if the main tag is an unknown program/style.
  # Returns a hash of structured program info, or nil if not applicable / on error.
  def research_unknown_program
    return nil if @main_tag.nil?
    return nil if known_program?

    research_program(@main_tag.name)
  rescue => e
    Rails.logger.warn("WorkoutLLMGenerator: research pass failed for '#{@main_tag&.name}': #{e.message}")
    nil
  end

  # Makes a fast, cheap LLM call to look up a fitness program by name.
  def research_program(program_name)
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

    call_llm(prompt, tools: [ RESEARCH_TOOL_DEFINITION ], tool_choice: { type: "any" }, max_tokens: 1500)
  end

  # Formats the research result into a prompt section.
  def build_program_research_context(research)
    return nil if research.blank?
    return nil if research["skipped"].present?

    lines = []
    lines << "## Program Context: #{@main_tag&.name}"
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
      research["typical_exercises"].each { |ex| lines << "  - #{ex}" }
    end

    if Array(research["signature_characteristics"]).any?
      lines << "\n**What makes it feel like #{@main_tag&.name}:**"
      research["signature_characteristics"].each { |c| lines << "  - #{c}" }
    end

    lines << "\nThe session MUST feel authentically like #{@main_tag&.name}. Follow the structure and use the exercises above — someone who has attended a real class should recognise it immediately."

    lines.join("\n")
  end

  def call_llm(prompt, tools: [ TOOL_DEFINITION ], tool_choice: { type: "any" }, max_tokens: 4096)
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
      if e.message.to_sym.in?(%i[overloaded rate_limited server_error]) && retries < 3
        wait = [ 2 ** retries, 8 ].min  # 1s, 2s, 4s (capped at 8s)
        Rails.logger.warn "LLM call #{e.message} — retry #{retries + 1}/3 after #{wait}s"
        sleep wait
        retries += 1
        retry
      end
      raise WorkoutGenerationError, case e.message.to_sym
      when :overloaded    then "The AI service is currently overloaded. Please try again in a moment."
      when :rate_limited  then "Too many requests. Please wait a moment and try again."
      when :server_error  then "The AI service is temporarily unavailable. Please try again shortly."
      else e.message
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
