module User::ExerciseWeightRecorder
  extend ActiveSupport::Concern

  def record_weights_from_workout(structure)
    return unless structure.is_a?(Hash)

    updates = {}
    Array(structure["sections"]).each do |section|
      Array(section["exercises"]).each do |exercise|
        name = exercise["name"].to_s.strip
        kg   = exercise["weight_kg"]
        next if name.blank? || kg.blank? || kg.to_f <= 0
        normalized = name.downcase.gsub(/[^a-z0-9\s]/, "").strip.gsub(/\s+/, "_")
        updates[normalized] = kg.to_f
      end
    end

    return if updates.empty?
    update_column(:exercise_weights, (exercise_weights || {}).merge(updates))
  end
end
