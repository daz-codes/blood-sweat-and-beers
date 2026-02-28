class WorkoutLike < ApplicationRecord
  belongs_to :user
  belongs_to :workout

  validates :user_id, uniqueness: { scope: :workout_id }
end
