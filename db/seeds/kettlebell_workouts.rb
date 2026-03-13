# ---------------------------------------------------------------------------
# Kettlebell Workouts — Weekly Programme Seed Data
# 7 days × 3 durations (30 / 45 / 60 min) = 21 workouts
# All assume two kettlebells. Used as LLM context for kettlebell session generation.
# ---------------------------------------------------------------------------

WARMUP = {
  "name"          => "Warm-up",
  "format"        => "straight",
  "duration_mins" => 5,
  "exercises" => [
    { "name" => "Star Jumps",                               "duration_s" => 45 },
    { "name" => "High Knees",                               "duration_s" => 45 },
    { "name" => "Downward Dog to World's Greatest Stretch", "duration_s" => 150, "notes" => "Flow slowly between positions" },
    { "name" => "Standing Burpees",                        "duration_s" => 60 }
  ]
}.freeze

COOLDOWN = {
  "name"          => "Cool-down",
  "format"        => "straight",
  "duration_mins" => 5,
  "exercises" => [
    { "name" => "Hip flexor stretch",            "notes" => "60s each side" },
    { "name" => "Hamstring stretch",             "notes" => "60s each side" },
    { "name" => "Wrist circles and forearm stretch", "notes" => "30s each direction" },
    { "name" => "Thoracic rotation",             "notes" => "30s each side" }
  ]
}.freeze

# Shared section blocks
EMOM16_LADDER_PULL_PUSH = {
  "name"         => "EMOM Ladder — Pull & Push (Mins 1–8)",
  "format"       => "ladder",
  "duration_mins" => 8,
  "varies"       => "reps",
  "start"        => 1,
  "end"          => 8,
  "step"         => 1,
  "notes"        => "EMOM style — complete reps then rest for remainder of the minute",
  "exercises" => [
    { "name" => "KB Row" },
    { "name" => "KB Clean" },
    { "name" => "KB Press" },
    { "name" => "KB High Pull" }
  ]
}.freeze

EMOM16_LADDER_LEGS = {
  "name"         => "EMOM Ladder — Legs (Mins 9–16)",
  "format"       => "ladder",
  "duration_mins" => 8,
  "varies"       => "reps",
  "start"        => 1,
  "end"          => 8,
  "step"         => 1,
  "notes"        => "EMOM style — complete reps then rest for remainder of the minute",
  "exercises" => [
    { "name" => "KB Clean Squat" },
    { "name" => "KB Front Squat" },
    { "name" => "Squat Jump" }
  ]
}.freeze

MONDAY_AMRAP12 = {
  "name"         => "AMRAP 12",
  "format"       => "amrap",
  "duration_mins" => 12,
  "exercises" => [
    { "name" => "KB Deadlift",                   "reps" => 8 },
    { "name" => "KB Power Clean",                "reps" => 8 },
    { "name" => "KB Thruster",                   "reps" => 8 },
    { "name" => "KB Row",                        "reps" => 8 },
    { "name" => "KB Reverse Lunge (Rack Position)", "reps" => 8 }
  ]
}.freeze

MONDAY_EMOM10 = {
  "name"         => "EMOM 10",
  "format"       => "emom",
  "duration_mins" => 10,
  "exercises" => [
    { "name" => "Press Ups",      "reps" => 6 },
    { "name" => "Shoulder Taps",  "reps" => 6 },
    { "name" => "Burpees",        "reps" => 6 }
  ]
}.freeze

MONDAY_ABS = {
  "name"         => "Core — 45/15 Intervals",
  "format"       => "straight",
  "duration_mins" => 5,
  "notes"        => "45s work / 15s rest each exercise",
  "exercises" => [
    { "name" => "Hip Rock",          "notes" => "45s" },
    { "name" => "Leg Raises",        "notes" => "45s" },
    { "name" => "Bicycle Kicks",     "notes" => "45s" },
    { "name" => "Heel Taps",         "notes" => "45s" },
    { "name" => "Full Body Crunch",  "notes" => "45s" }
  ]
}.freeze

TUESDAY_METCON16 = {
  "name"         => "MetCon 16",
  "format"       => "for_time",
  "duration_mins" => 16,
  "notes"        => "Burpees act as punctuation between each main movement — keep moving",
  "exercises" => [
    { "name" => "Burpee",      "reps" => 20 },
    { "name" => "KB Swing",    "reps" => 60 },
    { "name" => "Burpee",      "reps" => 20 },
    { "name" => "KB Squat",    "reps" => 40 },
    { "name" => "Burpee",      "reps" => 20 },
    { "name" => "Man Makers",  "reps" => 20, "notes" => "Double KB — row, row, push up, clean, squat, press" },
    { "name" => "Burpee",      "reps" => 20 }
  ]
}.freeze

TUESDAY_ABS = {
  "name"         => "Core AMRAP 5",
  "format"       => "amrap",
  "duration_mins" => 5,
  "exercises" => [
    { "name" => "KB Russian Twist",  "reps" => 20 },
    { "name" => "V Up",              "reps" => 10 },
    { "name" => "Straight Leg Raise", "reps" => 10 }
  ]
}.freeze

TUESDAY_AMRAP12 = {
  "name"         => "AMRAP 12",
  "format"       => "amrap",
  "duration_mins" => 12,
  "exercises" => [
    { "name" => "KB Clean Squat", "reps" => 10 },
    { "name" => "Press Up",       "reps" => 10 },
    { "name" => "Tuck Jump",      "reps" => 10 },
    { "name" => "KB Row",         "reps" => 10 }
  ]
}.freeze

TUESDAY_LADDER10 = {
  "name"         => "Ladder 10",
  "format"       => "ladder",
  "duration_mins" => 10,
  "varies"       => "reps",
  "start"        => 1,
  "end"          => 10,
  "step"         => 1,
  "exercises" => [
    { "name" => "KB Deadlift" },
    { "name" => "KB High Pull" },
    { "name" => "KB Press" },
    { "name" => "KB Reverse Lunge" }
  ]
}.freeze

WED_AMRAP8_SQUATS = {
  "name"         => "AMRAP 8 — Squats",
  "format"       => "amrap",
  "duration_mins" => 8,
  "exercises" => [
    { "name" => "KB Double Front Rack Squat", "reps" => 10 }
  ]
}.freeze

WED_AMRAP8_CLEAN_PRESS = {
  "name"         => "AMRAP 8 — Clean & Press",
  "format"       => "amrap",
  "duration_mins" => 8,
  "exercises" => [
    { "name" => "KB Clean and Press", "reps" => 5, "notes" => "Double KB — clean then press overhead" }
  ]
}.freeze

WED_ABS_45_15 = {
  "name"         => "Core — 45/15 Intervals",
  "format"       => "straight",
  "duration_mins" => 7,
  "notes"        => "45s work / 15s rest each exercise",
  "exercises" => [
    { "name" => "Shoulder Taps",   "notes" => "45s" },
    { "name" => "Mountain Climbers", "notes" => "45s" },
    { "name" => "Knee to Elbow",   "notes" => "45s" },
    { "name" => "KB Thrusters",    "notes" => "45s — light weight, constant movement" },
    { "name" => "Plank",           "notes" => "45s" },
    { "name" => "Side Plank Left", "notes" => "45s" },
    { "name" => "Side Plank Right", "notes" => "45s" }
  ]
}.freeze

WED_AMRAP12 = {
  "name"         => "AMRAP 12",
  "format"       => "amrap",
  "duration_mins" => 12,
  "notes"        => "Press ups intentionally bookend the circuit",
  "exercises" => [
    { "name" => "Press Up",                    "reps" => 10 },
    { "name" => "KB Row",                      "reps" => 8 },
    { "name" => "KB Swing",                    "reps" => 10 },
    { "name" => "KB Reverse Lunge (Rack)",     "reps" => 8 },
    { "name" => "Press Up",                    "reps" => 10 }
  ]
}.freeze

WED_ABS_AMRAP = {
  "name"         => "Core AMRAP 5",
  "format"       => "amrap",
  "duration_mins" => 5,
  "exercises" => [
    { "name" => "KB Full Body Crunch", "reps" => 15, "notes" => "Lying flat, KB overhead, crunch knees to chest as you bring KB forward" }
  ]
}.freeze

WED_TABATA10 = {
  "name"         => "Tabata 10",
  "format"       => "rounds",
  "rounds"       => 4,
  "duration_mins" => 10,
  "notes"        => "20s work / 10s rest, cycle through all 5 exercises = 2.5 min per round × 4",
  "exercises" => [
    { "name" => "Fast Feet Sprawls",  "duration_s" => 20 },
    { "name" => "Tuck Jump",          "duration_s" => 20 },
    { "name" => "Squat Jump",         "duration_s" => 20 },
    { "name" => "Mountain Climbers",  "duration_s" => 20 },
    { "name" => "Plank",              "duration_s" => 20 }
  ]
}.freeze

THU_TABATA20 = {
  "name"         => "40/20 Intervals × 4 Rounds",
  "format"       => "rounds",
  "rounds"       => 4,
  "duration_mins" => 20,
  "notes"        => "40s work / 20s rest each exercise — full effort on every interval",
  "exercises" => [
    { "name" => "Switch Lunge",          "duration_s" => 40 },
    { "name" => "Burpee",                "duration_s" => 40 },
    { "name" => "Tempo Press Up",        "duration_s" => 40, "notes" => "3 seconds down" },
    { "name" => "Tabletop Glute Bridge", "duration_s" => 40, "notes" => "Full extension, squeeze glutes" },
    { "name" => "Full Sit Up",           "duration_s" => 40 }
  ]
}.freeze

THU_ABS7 = {
  "name"         => "Core — 45/15 Intervals",
  "format"       => "straight",
  "duration_mins" => 7,
  "notes"        => "45s work / 15s rest each exercise",
  "exercises" => [
    { "name" => "Shoulder Taps",   "notes" => "45s" },
    { "name" => "Mountain Climbers", "notes" => "45s" },
    { "name" => "Knee to Elbow",   "notes" => "45s" },
    { "name" => "KB Thrusters",    "notes" => "45s — light KB" },
    { "name" => "Plank",           "notes" => "45s" },
    { "name" => "Side Plank Left", "notes" => "45s" },
    { "name" => "Side Plank Right", "notes" => "45s" }
  ]
}.freeze

THU_AMRAP12 = {
  "name"         => "AMRAP 12",
  "format"       => "amrap",
  "duration_mins" => 12,
  "exercises" => [
    { "name" => "KB Swing",          "reps" => 10 },
    { "name" => "KB Row",            "reps" => 10 },
    { "name" => "KB Thruster",       "reps" => 10 },
    { "name" => "KB Reverse Lunge",  "reps" => 10 }
  ]
}.freeze

THU_EMOM10 = {
  "name"         => "EMOM 10",
  "format"       => "emom",
  "duration_mins" => 10,
  "exercises" => [
    { "name" => "Man Makers",   "reps" => 5, "notes" => "Double KB — row, row, push up, clean, squat, press" },
    { "name" => "Jump Squats",  "reps" => 10 }
  ]
}.freeze

FRI_METCON16 = {
  "name"         => "MetCon 16 — Burpee Tax",
  "format"       => "for_time",
  "duration_mins" => 16,
  "notes"        => "Every 4 minutes: stop and complete 10 burpees as a penalty before continuing",
  "exercises" => [
    { "name" => "KB Swing Squat",  "reps" => 50, "notes" => "Swing to shoulder height, sit into squat" },
    { "name" => "KB Power Clean",  "reps" => 50 },
    { "name" => "KB Thruster",     "reps" => 50 }
  ]
}.freeze

FRI_LADDER12 = {
  "name"         => "Ladder 12 — Burpee Tax",
  "format"       => "ladder",
  "duration_mins" => 12,
  "varies"       => "reps",
  "start"        => 1,
  "end"          => 12,
  "step"         => 1,
  "notes"        => "Every 2 minutes: stop and complete 5 burpees before moving to the next rung",
  "exercises" => [
    { "name" => "KB High Pull" },
    { "name" => "KB Press" },
    { "name" => "KB Squat" },
    { "name" => "KB Row" }
  ]
}.freeze

FRI_ABS = {
  "name"         => "Core — 60/60 Intervals",
  "format"       => "straight",
  "duration_mins" => 10,
  "notes"        => "60s work / 60s rest each exercise",
  "exercises" => [
    { "name" => "Bicycle Kicks", "notes" => "60s — control the movement" },
    { "name" => "Hollow Hold",   "notes" => "60s — lower back pressed to floor" },
    { "name" => "Knee to Elbow", "notes" => "60s — alternate sides" },
    { "name" => "High Plank",    "notes" => "60s — hands under shoulders" },
    { "name" => "Low Plank",     "notes" => "60s — on forearms" }
  ]
}.freeze

FRI_AMRAP10 = {
  "name"         => "AMRAP 10",
  "format"       => "amrap",
  "duration_mins" => 10,
  "exercises" => [
    { "name" => "Gorilla Row",           "reps" => 20, "notes" => "KB on floor, alternate rows" },
    { "name" => "Hand Release Press Up", "reps" => 20, "notes" => "Hands off floor at bottom of each rep" }
  ]
}.freeze

SAT_EMOM16 = {
  "name"         => "EMOM 16",
  "format"       => "emom",
  "duration_mins" => 16,
  "notes"        => "4-exercise rotation: min 1 Clean, min 2 Squat, min 3 Press, min 4 Row — repeat × 4",
  "exercises" => [
    { "name" => "KB Clean",  "reps" => 6 },
    { "name" => "KB Squat",  "reps" => 6 },
    { "name" => "KB Press",  "reps" => 6 },
    { "name" => "KB Row",    "reps" => 6 }
  ]
}.freeze

SAT_ABS = {
  "name"         => "Core",
  "format"       => "straight",
  "duration_mins" => 5,
  "exercises" => [
    { "name" => "KB Russian Twist", "reps" => 20 },
    { "name" => "Sit Up",           "reps" => 15 },
    { "name" => "Leg Raise",        "reps" => 10 }
  ]
}.freeze

SAT_AMRAP12 = {
  "name"         => "AMRAP 12",
  "format"       => "amrap",
  "duration_mins" => 12,
  "exercises" => [
    { "name" => "KB Swing",         "reps" => 10 },
    { "name" => "KB Thruster",      "reps" => 10 },
    { "name" => "Burpee",           "reps" => 10 },
    { "name" => "KB Reverse Lunge", "reps" => 10 }
  ]
}.freeze

SAT_LADDER10 = {
  "name"         => "Ladder 10",
  "format"       => "ladder",
  "duration_mins" => 10,
  "varies"       => "reps",
  "start"        => 1,
  "end"          => 10,
  "step"         => 1,
  "exercises" => [
    { "name" => "KB Row" },
    { "name" => "KB Clean" },
    { "name" => "KB Press" },
    { "name" => "KB Front Squat" }
  ]
}.freeze

SUN_AMRAP20 = {
  "name"         => "AMRAP 20",
  "format"       => "amrap",
  "duration_mins" => 20,
  "exercises" => [
    { "name" => "KB Swing",        "reps" => 10 },
    { "name" => "KB Goblet Squat", "reps" => 10 },
    { "name" => "Push Up",         "reps" => 10 },
    { "name" => "KB Row",          "reps" => 10 }
  ]
}.freeze

SUN_EMOM10 = {
  "name"         => "EMOM 10",
  "format"       => "emom",
  "duration_mins" => 10,
  "exercises" => [
    { "name" => "Jump Squat",         "reps" => 10 },
    { "name" => "Mountain Climbers",  "reps" => 10, "notes" => "Count each leg" }
  ]
}.freeze

SUN_AMRAP10 = {
  "name"         => "AMRAP 10",
  "format"       => "amrap",
  "duration_mins" => 10,
  "exercises" => [
    { "name" => "KB Clean",   "reps" => 10 },
    { "name" => "KB Thruster", "reps" => 10 },
    { "name" => "Burpee",     "reps" => 10 }
  ]
}.freeze

SUN_ABS = {
  "name"         => "Core",
  "format"       => "straight",
  "duration_mins" => 5,
  "exercises" => [
    { "name" => "Hollow Hold",    "duration_s" => 30, "notes" => "Lower back pressed to floor throughout" },
    { "name" => "Bicycle Kicks",  "reps" => 20 },
    { "name" => "Heel Taps",      "reps" => 20 }
  ]
}.freeze

kettlebell_workouts = [

  # ─── MONDAY ────────────────────────────────────────────────────────────────

  {
    name:          "KB Ladder Rising",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Chase the ladder — keep the EMOM honest. Rest only what the minute allows.",
      "sections" => [ WARMUP, EMOM16_LADDER_PULL_PUSH, EMOM16_LADDER_LEGS, MONDAY_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Rise and Grind",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Ladder builds the engine, AMRAP tests it. Hold your pace on the AMRAP — aim for consistent rounds.",
      "sections" => [ WARMUP, EMOM16_LADDER_PULL_PUSH, EMOM16_LADDER_LEGS, MONDAY_AMRAP12, MONDAY_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Monday Full Stack",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "Three blocks, zero excuses. The EMOM10 at the end is where character is built.",
      "sections" => [ WARMUP, EMOM16_LADDER_PULL_PUSH, EMOM16_LADDER_LEGS, MONDAY_AMRAP12, MONDAY_EMOM10, MONDAY_ABS, COOLDOWN ]
    }
  },

  # ─── TUESDAY ───────────────────────────────────────────────────────────────

  {
    name:          "Burpee Gauntlet",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "The burpees between movements are the test. Don't slow down just because something hard is coming.",
      "sections" => [ WARMUP, TUESDAY_METCON16, TUESDAY_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Swing and Suffer",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "MetCon sets the tone. AMRAP keeps the pressure on. Consistent effort wins.",
      "sections" => [ WARMUP, TUESDAY_METCON16, TUESDAY_AMRAP12, TUESDAY_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Man Maker Tuesday",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "Three blocks of pain. Man Makers in the MetCon will break you — that's the point.",
      "sections" => [ WARMUP, TUESDAY_METCON16, TUESDAY_AMRAP12, TUESDAY_LADDER10, TUESDAY_ABS, COOLDOWN ]
    }
  },

  # ─── WEDNESDAY ─────────────────────────────────────────────────────────────

  {
    name:          "Double AMRAP",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Two single-movement AMRAPs — the simplicity is the challenge. How many rounds can you rack up?",
      "sections" => [ WARMUP, WED_AMRAP8_SQUATS, WED_AMRAP8_CLEAN_PRESS, WED_ABS_45_15, COOLDOWN ]
    }
  },

  {
    name:          "Push Pull Squat",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Focus on the full-body pattern — squat, pull, push. Breathe between movements.",
      "sections" => [ WARMUP, WED_AMRAP8_SQUATS, WED_AMRAP8_CLEAN_PRESS, WED_AMRAP12, WED_ABS_AMRAP, COOLDOWN ]
    }
  },

  {
    name:          "Wednesday Wrecking Ball",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "The tabata block is the wildcard. Everything before it is fuel, everything after is survival.",
      "sections" => [ WARMUP, WED_AMRAP8_SQUATS, WED_AMRAP8_CLEAN_PRESS, WED_AMRAP12, WED_TABATA10, WED_ABS_AMRAP, COOLDOWN ]
    }
  },

  # ─── THURSDAY ──────────────────────────────────────────────────────────────

  {
    name:          "40/20 Thunder",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Four rounds of five movements. The 40s intervals are longer than they sound. Stay moving.",
      "sections" => [ WARMUP, THU_TABATA20, THU_ABS7, COOLDOWN ]
    }
  },

  {
    name:          "Thunder and Chase",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Tabata warms up the engine, AMRAP runs it hard. Don't coast on the intervals.",
      "sections" => [ WARMUP, THU_TABATA20, THU_AMRAP12, THU_ABS7, COOLDOWN ]
    }
  },

  {
    name:          "Jump and Suffer",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "The EMOM10 at the end separates sessions from workouts. Man Makers under fatigue are brutal — that's the goal.",
      "sections" => [ WARMUP, THU_TABATA20, THU_AMRAP12, THU_EMOM10, THU_ABS7, COOLDOWN ]
    }
  },

  # ─── FRIDAY ────────────────────────────────────────────────────────────────

  {
    name:          "The Taxman",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Every 4 minutes the taxman comes. Pay up and keep moving — don't let the penalty break your rhythm.",
      "sections" => [ WARMUP, FRI_METCON16, FRI_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Ladder and Tax",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Two time-pressured blocks. The MetCon breaks you down, the Ladder rebuilds you — with interest.",
      "sections" => [ WARMUP, FRI_METCON16, FRI_LADDER12, FRI_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Full Audit",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "Three blocks, all business. The AMRAP10 is a reward — but only if you've earned it.",
      "sections" => [ WARMUP, FRI_METCON16, FRI_LADDER12, FRI_AMRAP10, FRI_ABS, COOLDOWN ]
    }
  },

  # ─── SATURDAY ──────────────────────────────────────────────────────────────

  {
    name:          "Six Gun EMOM",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Six reps, every minute, four movements. Deceptively simple — consistently brutal.",
      "sections" => [ WARMUP, SAT_EMOM16, SAT_ABS, COOLDOWN ]
    }
  },

  {
    name:          "EMOM + Chaos",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Structured EMOM builds the base; open AMRAP reveals how much you have left.",
      "sections" => [ WARMUP, SAT_EMOM16, SAT_AMRAP12, SAT_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Saturday Staircase",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "EMOM builds discipline, AMRAP tests fitness, Ladder pushes volume. Three different gears.",
      "sections" => [ WARMUP, SAT_EMOM16, SAT_AMRAP12, SAT_LADDER10, SAT_ABS, COOLDOWN ]
    }
  },

  # ─── SUNDAY ────────────────────────────────────────────────────────────────

  {
    name:          "Long Sunday",
    activity:      "Kettlebell",
    duration_mins: 30,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Sunday is about movement, not suffering. Smooth and steady — stack up the rounds.",
      "sections" => [ WARMUP, SUN_AMRAP20, SUN_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Sunday Build",
    activity:      "Kettlebell",
    duration_mins: 45,
    difficulty:    "intermediate",
    structure: {
      "goal"     => "Long AMRAP sets the rhythm, EMOM adds a tempo spike at the end. Finish strong.",
      "sections" => [ WARMUP, SUN_AMRAP20, SUN_EMOM10, SUN_ABS, COOLDOWN ]
    }
  },

  {
    name:          "Weekend Finisher",
    activity:      "Kettlebell",
    duration_mins: 60,
    difficulty:    "advanced",
    structure: {
      "goal"     => "End the week with intent. Three blocks, each harder than it looks. Leave nothing.",
      "sections" => [ WARMUP, SUN_AMRAP20, SUN_EMOM10, SUN_AMRAP10, SUN_ABS, COOLDOWN ]
    }
  }

]

system_user = User.find_by!(email_address: "system@volt.app")

puts "Seeding kettlebell workouts..."

kettlebell_activity = Activity.find_or_create_by!(name: "Kettlebell")

kettlebell_workouts.each do |attrs|
  attrs.delete(:activity)  # remove the string, use the record
  workout = Workout.find_or_initialize_by(name: attrs[:name], user: system_user)
  workout.assign_attributes(attrs.merge(status: "active", activity: kettlebell_activity))
  workout.save!

  puts "  #{workout.name} [Kettlebell]"
end

puts "Done. #{kettlebell_workouts.size} kettlebell workouts seeded."
