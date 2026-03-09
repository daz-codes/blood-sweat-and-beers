module FitnessTests
  # unit: "time" (stored as seconds), "m" (metres), "kg", "reps", "cal", "rounds"
  # scoring: :lower (time — faster is better), :higher (everything else)

  CATEGORIES = [
    {
      key: "running",
      name: "Running",
      tests: [
        { key: "cooper_run", name: "Cooper Run (12 min)", unit: "m",    scoring: :higher, hint: "Distance covered in 12 minutes — a classic aerobic fitness test", benchmark: true, match_terms: ["cooper"] },
        { key: "run_1mile",  name: "1 Mile Run",          unit: "time", scoring: :lower  },
        { key: "run_5km",    name: "5km Run",             unit: "time", scoring: :lower  },
      ]
    },
    {
      key: "rowing",
      name: "Rowing (Concept2)",
      tests: [
        { key: "row_500m",  name: "Row 500m",  unit: "time", scoring: :lower, hint: "All-out sprint — pure power", benchmark: true, match_terms: ["row", "500"] },
        { key: "row_2000m", name: "Row 2000m", unit: "time", scoring: :lower, hint: "The universal rowing benchmark", benchmark: true, match_terms: ["row", "2000"] },
      ]
    },
    {
      key: "ski_erg",
      name: "Ski Erg (Concept2)",
      tests: [
        { key: "ski_500m",  name: "Ski Erg 500m",  unit: "time", scoring: :lower, hint: "All-out sprint effort", match_terms: ["ski", "500"] },
        { key: "ski_2000m", name: "Ski Erg 2000m", unit: "time", scoring: :lower, match_terms: ["ski", "2000"] },
      ]
    },
    {
      key: "assault_bike",
      name: "Assault / Echo Bike",
      tests: [
        { key: "bike_25cal",  name: "Assault Bike 25 cal",  unit: "time", scoring: :lower, hint: "Short, sharp sprint", match_terms: ["assault", "25"] },
        { key: "bike_50cal",  name: "Assault Bike 50 cal",  unit: "time", scoring: :lower, match_terms: ["assault", "50"] },
        { key: "bike_100cal", name: "Assault Bike 100 cal", unit: "time", scoring: :lower, hint: "The classic assault bike test", match_terms: ["assault", "100"] },
      ]
    },
    {
      key: "strength",
      name: "Strength",
      tests: [
        { key: "squat_1rm",    name: "Back Squat 1RM",     unit: "kg", scoring: :higher },
        { key: "deadlift_1rm", name: "Deadlift 1RM",       unit: "kg", scoring: :higher },
        { key: "bench_1rm",    name: "Bench Press 1RM",    unit: "kg", scoring: :higher },
        { key: "ohp_1rm",      name: "Overhead Press 1RM", unit: "kg", scoring: :higher },
        { key: "squat_5rm",    name: "Back Squat 5RM",     unit: "kg", scoring: :higher },
        { key: "deadlift_5rm", name: "Deadlift 5RM",       unit: "kg", scoring: :higher, benchmark: true, match_terms: ["deadlift", "5rm"] },
        { key: "bench_5rm",    name: "Bench Press 5RM",    unit: "kg", scoring: :higher },
      ]
    },
    {
      key: "bodyweight",
      name: "Bodyweight",
      tests: [
        { key: "pressup_1min", name: "Press-ups 1 min", unit: "reps", scoring: :higher, benchmark: true, match_terms: ["press", "1 min"] },
        { key: "pullup_1min",  name: "Pull-ups 1 min",  unit: "reps", scoring: :higher, benchmark: true, match_terms: ["pull", "1 min"] },
      ]
    },
    {
      key: "functional",
      name: "Functional Tests",
      tests: [
        { key: "volt_25",           name: "25 Clean & Press + 25 Thrusters", unit: "time", scoring: :lower, hint: "For time — 45kg/30kg. The Volt benchmark.", benchmark: true, match_terms: ["clean", "press", "thruster"] },
        { key: "clean_press_30_45", name: "30 Clean & Press (45/30 kg)",     unit: "time", scoring: :lower, match_terms: ["clean", "press", "30"] },
        { key: "thrusters_100_30",  name: "100 Thrusters (30/20 kg)",        unit: "time", scoring: :lower, match_terms: ["thruster", "100"] },
      ]
    },
  ].freeze

  ALL            = CATEGORIES.flat_map { |c| c[:tests] }.freeze
  BY_KEY         = ALL.index_by { |t| t[:key] }.freeze
  ALL_KEYS       = ALL.map { |t| t[:key] }.freeze
  BENCHMARKS     = ALL.select { |t| t[:benchmark] }.freeze
  BENCHMARK_KEYS = BENCHMARKS.map { |t| t[:key] }.freeze

  def self.find(key)
    BY_KEY[key.to_s]
  end

  def self.category_for(key)
    CATEGORIES.find { |c| c[:tests].any? { |t| t[:key] == key.to_s } }
  end
end
