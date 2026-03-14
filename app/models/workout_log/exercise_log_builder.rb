module WorkoutLog::ExerciseLogBuilder
  extend ActiveSupport::Concern

  def create_exercise_logs_from_structure(structure, step_times = {})
    if structure.is_a?(Hash)
      create_exercise_logs_from_sections(structure)
    else
      create_exercise_logs_legacy(structure, step_times)
    end
  end

  private

  def create_exercise_logs_from_sections(structure)
    Array(structure["sections"]).each_with_index do |section, si|
      Array(section["exercises"]).each_with_index do |ex, ei|
        name = ex["name"].to_s.strip
        next if name.blank?

        set = { "name" => name, "completed" => true }
        set["reps"]       = ex["reps"].to_i      if ex["reps"].to_i > 0
        set["weight_kg"]  = ex["weight_kg"].to_f if ex["weight_kg"].to_f > 0
        set["distance_m"] = ex["distance_m"].to_i if ex["distance_m"].to_i > 0
        set["duration_s"] = ex["duration_s"].to_i if ex["duration_s"].to_i > 0

        rounds = section["rounds"].to_i
        sets   = rounds > 1 ? Array.new(rounds) { set.dup } : [ set ]

        exercise_logs.create!(
          exercise_id: nil,
          step_order:  si * 100 + ei,
          sets_data:   sets
        )
      end
    end
  end

  def create_exercise_logs_legacy(structure, step_times)
    structure.each do |step|
      order    = step["order"].to_i
      raw_time = step_times[order.to_s].presence

      next unless raw_time

      time_s = self.class.parse_time(raw_time)
      next unless time_s

      set_data = { "time_s" => time_s }
      set_data["distance_m"] = step["distance_m"] if step["distance_m"]
      set_data["reps"]       = step["reps"]        if step["reps"]
      set_data["weight_kg"]  = step["weight_kg"]   if step["weight_kg"]

      exercise_logs.create!(
        exercise_id: step["exercise_id"],
        step_order:  order,
        sets_data:   [ set_data ]
      )
    end
  end

  # Accepts "5:30", "330" (raw seconds)
  def self.parse_time(str)
    str = str.to_s.strip
    if str.match?(/\A\d+:\d{2}\z/)
      parts = str.split(":")
      parts[0].to_i * 60 + parts[1].to_i
    elsif str.match?(/\A\d+\z/)
      str.to_i
    end
  end
end
