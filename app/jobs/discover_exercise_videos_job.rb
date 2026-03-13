class DiscoverExerciseVideosJob < ApplicationJob
  queue_as :default

  def perform(workout_id)
    workout = Workout.find_by(id: workout_id)
    return unless workout&.structure.is_a?(Hash)

    sections = Array(workout.structure["sections"])
    exercise_names = sections.flat_map { |s| Array(s["exercises"]).map { |e| e["name"] } }.compact.uniq

    exercise_names.each do |name|
      slug = ExerciseVideo.slugify(name)
      next if ExerciseVideo.exists?(slug: slug)

      ExerciseVideoLookup.call(name)
    end
  end
end
