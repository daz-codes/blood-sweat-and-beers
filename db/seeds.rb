# ---------------------------------------------------------------------------
# System user — owns seeded workouts
# ---------------------------------------------------------------------------
system_user = User.find_or_create_by!(email_address: "system@bloodsweatbeers.app") do |u|
  u.password = SecureRandom.hex(24)
end
puts "System user: #{system_user.email_address}"

# ---------------------------------------------------------------------------
# Helper: find or create a tag by name
# ---------------------------------------------------------------------------
def tag_for(name)
  Tag.find_or_create_by!(slug: name.parameterize) { |t| t.name = name }
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
      workout_type:  w["workout_type"],
      duration_mins: w["duration_mins"],
      difficulty:    w["difficulty"],
      tag_names:     w["tags"],
      structure:     w["structure"]
    }
  end
else
  puts "No db/seeds/workouts.json found — using hardcoded workouts."
  seeded_workouts = [
  {
    name:          "Engine + Carries",
    workout_type:  "custom",
    duration_mins: 30,
    difficulty:    "intermediate",
    tag_names:     %w[deka cardio carries],
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
    workout_type:  "custom",
    duration_mins: 35,
    difficulty:    "intermediate",
    tag_names:     %w[deka legs cardio],
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
    workout_type:  "custom",
    duration_mins: 40,
    difficulty:    "intermediate",
    tag_names:     %w[deka simulation cardio carries],
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
    workout_type:  "custom",
    duration_mins: 20,
    difficulty:    "intermediate",
    tag_names:     %w[deka simulation test],
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
  }
  ]
end

puts "Seeding workouts..."

seeded_workouts.each do |attrs|
  tag_names = attrs.delete(:tag_names)

  workout = Workout.find_or_initialize_by(name: attrs[:name], user: system_user)
  workout.assign_attributes(attrs.merge(status: "active"))
  workout.save!

  # Apply tags
  tags = tag_names.map { |n| tag_for(n) }
  workout.tags = tags

  puts "  #{workout.name} [#{tag_names.join(", ")}]"
end

puts "Done. #{Workout.where(user: system_user).count} seeded workouts."

# ---------------------------------------------------------------------------
# System user likes all seeded workouts (baseline for most_liked_with_tags)
# ---------------------------------------------------------------------------
puts "Seeding workout likes..."
Workout.where(user: system_user).each do |workout|
  WorkoutLike.find_or_create_by!(user: system_user, workout: workout)
end
puts "Done. #{WorkoutLike.count} workout likes."
