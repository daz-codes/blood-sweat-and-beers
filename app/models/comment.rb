class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :workout_log, counter_cache: true

  validates :body, presence: true, length: { maximum: 500 }

  scope :chronological, -> { order(created_at: :asc) }

  after_create_commit :notify_log_owner

  private

  def notify_log_owner
    owner = workout_log.user
    return if owner == user

    Notification.create!(
      recipient:  owner,
      actor:      user,
      notifiable: self,
      action:     "comment"
    )
  end
end
