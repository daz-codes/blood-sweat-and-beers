# Scans a saved workout's structure for weight_kg values and upserts them
# into the user's exercise_weights profile (jsonb). Called whenever a workout
# transitions to "active" status so the user's next generation can reference
# the weights they actually used.
class ExerciseWeightRecorder
  def self.call(user, structure)
    return unless structure.is_a?(Hash)

    updates = {}
    Array(structure["sections"]).each do |section|
      Array(section["exercises"]).each do |exercise|
        name = exercise["name"].to_s.strip
        kg   = exercise["weight_kg"]
        next if name.blank? || kg.blank? || kg.to_f <= 0
        updates[normalize(name)] = kg.to_f
      end
    end

    return if updates.empty?

    user.update_column(:exercise_weights, (user.exercise_weights || {}).merge(updates))
  end

  def self.normalize(name)
    name.downcase.gsub(/[^a-z0-9\s]/, "").strip.gsub(/\s+/, "_")
  end
end
