# ---------------------------------------------------------------------------
# System user — owns seeded workouts
# ---------------------------------------------------------------------------
system_user = User.find_or_create_by!(email_address: "system@volt.app") do |u|
  u.password = SecureRandom.hex(24)
end
puts "System user: #{system_user.email_address}"

# ---------------------------------------------------------------------------
# Seed default activities
# ---------------------------------------------------------------------------
Activity::DEFAULT_NAMES.each do |name|
  Activity.find_or_create_by!(name: name)
end
puts "Activities: #{Activity.count} seeded."

# ---------------------------------------------------------------------------
# Activity mapping for tag_names → activity (used by both JSON and hardcoded seeds)
# ---------------------------------------------------------------------------
TAG_TO_ACTIVITY = {
  "deka" => "Deka", "hyrox" => "Hyrox", "crossfit" => "CrossFit",
  "functional-fitness" => "Functional Fitness", "functional-muscle" => "Functional Muscle",
  "hiit" => "HIIT", "bodyweight" => "Bodyweight", "kettlebell" => "Kettlebell",
  "metafit" => "Metafit", "f45" => "F45", "strength" => "Strength",
  "dirty-dozen" => "Dirty Dozen", "barry-s-bootcamp" => "Barry's Bootcamp"
}.freeze

def activity_from_tag_names(tag_names)
  tag_names.each do |tn|
    slug = tn.to_s.parameterize
    return TAG_TO_ACTIVITY[slug] if TAG_TO_ACTIVITY.key?(slug)
  end
  nil
end

# ---------------------------------------------------------------------------
# Seeded workouts — loaded from db/seeds/workouts.json when present,
# otherwise falls back to the hardcoded list below.
# To regenerate the JSON: rails 'seed_workouts:export[your@email.com]'
# ---------------------------------------------------------------------------
json_path = Rails.root.join("db/seeds/workouts.json")

if json_path.exist?
  puts "Loading workouts from #{json_path}..."
  raw = JSON.parse(json_path.read)
  seeded_workouts = raw.map do |w|
    {
      name:          w["name"],
      activity:      w["activity"] || activity_from_tag_names(w["tags"] || []),
      duration_mins: w["duration_mins"],
      difficulty:    w["difficulty"],
      structure:     w["structure"]
    }
  end
else
  puts "No db/seeds/workouts.json found — using hardcoded workouts."
  seeded_workouts = [
  {
    name:          "Engine + Carries",
    activity:      "Deka",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        {
          "name"         => "Warm-up",
          "format"       => "straight",
          "duration_mins" => 5,
          "notes"        => "Easy row → bike. A few lunges + light carries."
        },
        {
          "name"         => "Main Set",
          "format"       => "amrap",
          "duration_mins" => 20,
          "exercises"    => [
            { "name" => "Row",            "distance_m" => 400, "notes" => "~1:45–1:50 pace" },
            { "name" => "Farmer's Carry", "distance_m" => 60,  "notes" => "heavy but unbroken" },
            { "name" => "Box Step-Overs", "reps"       => 15,  "notes" => "controlled" },
            { "name" => "Burpees",        "reps"       => 10 }
          ]
        }
      ],
      "duration_mins" => 25,
      "goal"          => "Heart rate up, never panic breathing. Finish thinking: I could do 5 more minutes."
    }
  },
  {
    name:          "Legs + Core + Bike Burn",
    activity:      "Deka",
    duration_mins: 35,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        {
          "name"         => "Warm-up",
          "format"       => "straight",
          "duration_mins" => 5,
          "notes"        => "Light movement prep."
        },
        {
          "name"      => "Main Set",
          "format"    => "rounds",
          "rounds"    => 4,
          "rest_secs" => 60,
          "exercises" => [
            { "name" => "Reverse Lunges",        "reps" => 30, "notes" => "loaded, unbroken" },
            { "name" => "Dead Ball Wall-Overs",   "reps" => 20 },
            { "name" => "Med Ball Sit-Up Throws", "reps" => 15 },
            { "name" => "Bike Erg",               "notes" => "25 cal @ ~1:20–1:30 pace" }
          ]
        }
      ],
      "duration_mins" => 35,
      "goal"          => "Legs under fatigue. Learn to bike while cooked. Keep lunges unbroken."
    }
  },
  {
    name:          "DEKA Simulation Intervals",
    activity:      "Deka",
    duration_mins: 40,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        {
          "name"         => "Warm-up",
          "format"       => "straight",
          "duration_mins" => 5,
          "notes"        => "Light movement prep."
        },
        {
          "name"      => "Simulation Intervals",
          "format"    => "rounds",
          "rounds"    => 3,
          "rest_secs" => 120,
          "exercises" => [
            { "name" => "SkiErg",         "distance_m" => 500, "notes" => "@1:55–2:00 pace" },
            { "name" => "Box Step-Overs", "reps"       => 20 },
            { "name" => "Farmer's Carry", "distance_m" => 100 },
            { "name" => "Bike Erg",       "notes"      => "25 cal @ ~1:25 pace" }
          ]
        },
        {
          "name"    => "Finisher",
          "format"  => "rounds",
          "rounds"  => 2,
          "exercises" => [
            { "name" => "Burpees",    "reps" => 15 },
            { "name" => "Wall Balls", "reps" => 15 }
          ]
        }
      ],
      "duration_mins" => 40,
      "goal"          => "Practice machine → legs → carry → machine. Control breathing. Fast, calm transitions."
    }
  },
  {
    name:          "Half-DEKA Test",
    activity:      "Deka",
    duration_mins: 20,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        {
          "name"      => "Half-DEKA",
          "format"    => "straight",
          "notes"     => "For time — but no redlining.",
          "exercises" => [
            { "name" => "Row",            "distance_m" => 500 },
            { "name" => "Lunges",         "reps"       => 20 },
            { "name" => "SkiErg",         "distance_m" => 500 },
            { "name" => "Bike Erg",       "notes"      => "25 cal" },
            { "name" => "Farmer's Carry", "distance_m" => 100 },
            { "name" => "Wall Balls",     "reps"       => 20 },
            { "name" => "Burpees",        "reps"       => 20 }
          ]
        }
      ],
      "duration_mins" => 20,
      "goal"          => "If you can finish this not wrecked, you're ready for DEKA."
    }
  },
  # CrossFit
  {
    name:          "Thrusters and Pull-ups",
    activity:      "CrossFit",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 5,
          "notes" => "Row 500m easy, then PVC pass-throughs, air squats, leg swings." },
        { "name" => "AMRAP 20", "format" => "amrap", "duration_mins" => 20,
          "exercises" => [
            { "name" => "Thrusters",  "reps" => 9,  "weight_kg" => 43, "notes" => "unbroken if possible" },
            { "name" => "Pull-ups",   "reps" => 15, "notes" => "kipping allowed" },
            { "name" => "Box Jumps",  "reps" => 12, "notes" => "24\" box, step down" }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Hip flexor stretch",  "notes" => "90s each side" },
            { "name" => "Shoulder distraction", "notes" => "60s each side on rig" },
            { "name" => "Hamstring stretch",    "notes" => "60s each side" }
          ] }
      ],
      "goal" => "Move fast and try to keep the thrusters unbroken. Record total rounds + reps."
    }
  },
  {
    name:          "Death by Deadlifts",
    activity:      "CrossFit",
    duration_mins: 45,
    difficulty:    "advanced",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 8,
          "notes" => "Assault bike 2 min easy, then barbell warm-up: 5 × deadlift + 5 × hang power clean, build to working weight." },
        { "name" => "For Time (cap 30 min)", "format" => "for_time",
          "exercises" => [
            { "name" => "Deadlifts",        "reps" => 21, "weight_kg" => 100 },
            { "name" => "Burpee Box Jumps", "reps" => 21 },
            { "name" => "Deadlifts",        "reps" => 15, "weight_kg" => 100 },
            { "name" => "Burpee Box Jumps", "reps" => 15 },
            { "name" => "Deadlifts",        "reps" => 9,  "weight_kg" => 100 },
            { "name" => "Burpee Box Jumps", "reps" => 9 }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Pigeon pose",       "notes" => "2 min each side" },
            { "name" => "Cat-cow",           "notes" => "10 slow reps" },
            { "name" => "Thoracic rotation", "notes" => "30s each side" }
          ] }
      ],
      "goal" => "Deadlifts should be touch-and-go or max 2 breaks per set. Record finishing time."
    }
  },
  # Functional Fitness
  {
    name:          "KB Complex + Carries",
    activity:      "Functional Fitness",
    duration_mins: 40,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 7,
          "notes" => "Halo × 10 each way, hip bridge × 15, lateral band walk × 10 each, shoulder circles." },
        { "name" => "KB Complex", "format" => "rounds", "rounds" => 4, "rest_secs" => 90,
          "exercises" => [
            { "name" => "KB Deadlift",       "reps" => 8,  "weight_kg" => 32, "notes" => "explosive hip hinge" },
            { "name" => "KB Swing",          "reps" => 15, "weight_kg" => 24, "notes" => "American — overhead" },
            { "name" => "KB Clean + Press",  "reps" => 6,  "weight_kg" => 20, "notes" => "3 each arm, no rest" },
            { "name" => "Farmer's Carry",    "distance_m" => 40, "weight_kg" => 28, "notes" => "per hand, heavy and calm" }
          ] },
        { "name" => "Finisher", "format" => "amrap", "duration_mins" => 6,
          "exercises" => [
            { "name" => "KB Snatch",    "reps" => 5, "weight_kg" => 20, "notes" => "5L / 5R alternating" },
            { "name" => "Ring Rows",    "reps" => 8, "notes" => "strict, chest to rings" }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Lat stretch on rig",   "notes" => "60s each side" },
            { "name" => "Hip flexor stretch",   "notes" => "90s each side" },
            { "name" => "Wrist circles",        "notes" => "30s each direction" }
          ] }
      ],
      "goal" => "Quality over speed. The carries should be heavy enough to feel your lats working."
    }
  },
  {
    name:          "Sled + Ropes + Rings",
    activity:      "Functional Fitness",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 8,
          "notes" => "Assault bike 3 min easy, band pull-aparts × 15, goblet squats × 10, hip 90-90 rotations." },
        { "name" => "Main Circuit", "format" => "rounds", "rounds" => 5, "rest_secs" => 90,
          "exercises" => [
            { "name" => "Sled Push",       "distance_m" => 20, "notes" => "heavy — nose-to-ground posture" },
            { "name" => "Battle Ropes",    "duration_s" => 30, "notes" => "alternating waves, full effort" },
            { "name" => "Ring Rows",       "reps" => 10, "notes" => "feet elevated" },
            { "name" => "DB Romanian DL",  "reps" => 10, "weight_kg" => 22, "notes" => "slow eccentric" }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Hamstring stretch", "notes" => "90s each side" },
            { "name" => "Chest opener",      "notes" => "doorway or rig, 60s" },
            { "name" => "Spinal rotation",   "notes" => "10 slow reps each side" }
          ] }
      ],
      "goal" => "The sled pushes should leave you breathless. Battle ropes are all-out. Ring rows are the recovery."
    }
  },
  # HIIT
  {
    name:          "Tabata Assault",
    activity:      "HIIT",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 7,
          "notes" => "Row 3 min easy, then jump rope 60s, leg swings, arm circles, 10 air squats." },
        { "name" => "Tabata Block 1 — Assault Bike", "format" => "tabata", "duration_mins" => 4,
          "exercises" => [ { "name" => "Assault Bike", "notes" => "MAX effort on every 20s interval" } ] },
        { "name" => "Rest", "format" => "straight", "duration_mins" => 3, "notes" => "Walk, slow breathing, get heart rate down." },
        { "name" => "Tabata Block 2 — KB Swings", "format" => "tabata", "duration_mins" => 4,
          "exercises" => [ { "name" => "KB Swing", "weight_kg" => 24, "notes" => "American — explosive hips each rep" } ] },
        { "name" => "Rest", "format" => "straight", "duration_mins" => 3, "notes" => "Walk it off." },
        { "name" => "Tabata Block 3 — Burpees", "format" => "tabata", "duration_mins" => 4,
          "exercises" => [ { "name" => "Burpees", "notes" => "Full extension at top, quick drop" } ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Hip flexor stretch", "notes" => "90s each side" },
            { "name" => "Quad stretch",       "notes" => "60s each side" },
            { "name" => "Forward fold",       "notes" => "90s, breathe deep" }
          ] }
      ],
      "goal" => "Each 20s interval is all-out. The rest is the workout. Three rounds of pain, then done."
    }
  },
  {
    name:          "30-30 Machine Intervals",
    activity:      "HIIT",
    duration_mins: 35,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 6,
          "notes" => "Easy rowing 3 min, then 2 rounds: 10 box step-ups + 10 banded pull-aparts + 10 hip bridges." },
        { "name" => "30/30 Intervals", "format" => "rounds", "rounds" => 8, "rest_secs" => 30,
          "exercises" => [ { "name" => "SkiErg", "duration_s" => 30, "notes" => "MAX effort — keep split time 5-10% below PB" } ] },
        { "name" => "Active Recovery", "format" => "straight", "duration_mins" => 3, "notes" => "Walk slowly. Shake out arms and legs." },
        { "name" => "Finisher", "format" => "rounds", "rounds" => 4, "rest_secs" => 20,
          "exercises" => [
            { "name" => "Box Jumps",  "reps" => 8, "notes" => "land soft, step down" },
            { "name" => "Push-ups",   "reps" => 10 }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Thoracic rotation",  "notes" => "30s each side" },
            { "name" => "Lat stretch",        "notes" => "60s each side on rig" },
            { "name" => "Standing quad hold", "notes" => "60s each side" }
          ] }
      ],
      "goal" => "The 30s rest is not enough. It's not supposed to be. Consistent pace every interval."
    }
  },
  # Bodyweight
  {
    name:          "Push-Pull EMOM",
    activity:      "Bodyweight",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 6,
          "notes" => "Arm circles, band pull-aparts, scapular push-ups × 10, dead hangs × 30s × 2." },
        { "name" => "EMOM 20", "format" => "emom", "duration_mins" => 20,
          "exercises" => [
            { "name" => "Min 1: Push-ups",   "reps" => 15, "notes" => "perfect form — full range" },
            { "name" => "Min 2: Pull-ups",   "reps" => 8,  "notes" => "dead hang start, chin over bar" },
            { "name" => "Min 3: Air Squats", "reps" => 20, "notes" => "slow down, explosive up" },
            { "name" => "Min 4: Hollow Hold", "duration_s" => 30, "notes" => "lower back on floor, legs low" }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Child's pose",      "notes" => "2 min" },
            { "name" => "Chest opener",      "notes" => "60s on floor, arms wide" },
            { "name" => "Hip flexor stretch", "notes" => "90s each side" }
          ] }
      ],
      "goal" => "Every minute, every rep. If you can't finish within the minute, reduce reps next round."
    }
  },
  {
    name:          "Jump and Grind",
    activity:      "Bodyweight",
    duration_mins: 35,
    difficulty:    "intermediate",
    structure: {
      "sections" => [
        { "name" => "Warm-up", "format" => "straight", "duration_mins" => 7,
          "notes" => "Jog on spot 2 min, leg swings, 10 squat jumps (easy), 10 walking lunges, calf raises × 15." },
        { "name" => "For Time", "format" => "for_time",
          "exercises" => [
            { "name" => "Jump Squats",    "reps" => 50, "notes" => "full squat depth, explode up" },
            { "name" => "Push-ups",       "reps" => 40 },
            { "name" => "Burpees",        "reps" => 30, "notes" => "full jump at top" },
            { "name" => "Reverse Lunges", "reps" => 40, "notes" => "alternating legs" },
            { "name" => "Mountain Climbers", "reps" => 60, "notes" => "count each leg" }
          ] },
        { "name" => "Cool-down", "format" => "straight", "duration_mins" => 5,
          "exercises" => [
            { "name" => "Quad stretch",     "notes" => "60s each side" },
            { "name" => "Calf stretch",     "notes" => "60s each side on step" },
            { "name" => "Pigeon pose",      "notes" => "2 min each side" }
          ] }
      ],
      "goal" => "Move fast but keep form. This one sneaks up on you — the push-ups after jump squats will humble you."
    }
  }
  ]
end

puts "Seeding workouts..."

seeded_workouts.each do |attrs|
  activity_name = attrs.delete(:activity)
  activity = activity_name.present? ? Activity.find_or_create_by!(name: activity_name) : nil

  workout = Workout.find_or_initialize_by(name: attrs[:name], user: system_user)
  workout.assign_attributes(attrs.merge(status: "active", activity: activity))
  workout.save!

  puts "  #{workout.name} [#{activity_name}]"
end

puts "Done. #{Workout.where(user: system_user).count} seeded workouts."

# ---------------------------------------------------------------------------
# System user likes all seeded workouts (baseline for most_liked_with_activity)
# ---------------------------------------------------------------------------
puts "Seeding workout likes..."
Workout.where(user: system_user).each do |workout|
  WorkoutLike.find_or_create_by!(user: system_user, workout: workout)
end
puts "Done. #{WorkoutLike.count} workout likes."

# ---------------------------------------------------------------------------
# Kettlebell weekly programme workouts
# ---------------------------------------------------------------------------
load Rails.root.join("db/seeds/kettlebell_workouts.rb")

puts "Seeding kettlebell workout likes..."
Workout.where(user: system_user).each do |workout|
  WorkoutLike.find_or_create_by!(user: system_user, workout: workout)
end
puts "Done. #{WorkoutLike.count} total workout likes."

# Exercise video lookup table
# ---------------------------------------------------------------------------
load Rails.root.join("db/seeds/exercise_videos.rb")
