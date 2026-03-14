class WorkoutLike < ApplicationRecord
  include Notifiable

  belongs_to :user
  belongs_to :workout

  validates :user_id, uniqueness: { scope: :workout_id }

  notifies action: :like, recipient: :workout_owner

  private

  def workout_owner
    workout.user
  end
end
