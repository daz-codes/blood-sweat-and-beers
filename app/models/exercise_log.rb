class ExerciseLog < ApplicationRecord
  belongs_to :workout_log
  belongs_to :exercise, optional: true  # nil for run steps
end
