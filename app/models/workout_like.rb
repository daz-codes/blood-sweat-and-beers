class WorkoutLike < ApplicationRecord
  belongs_to :user
  belongs_to :workout

  after_create_commit :notify_workout_owner

  private

  def notify_workout_owner
    owner = workout.user
    return if owner == user

    Notification.create!(
      recipient:  owner,
      actor:      user,
      notifiable: self,
      action:     "like"
    )
  end
end
