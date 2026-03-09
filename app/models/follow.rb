class Follow < ApplicationRecord
  belongs_to :follower,  class_name: "User"
  belongs_to :following, class_name: "User"

  validates :follower_id, uniqueness: { scope: :following_id }
  validate  :cannot_follow_self

  before_create { self.requested_at = Time.current }

  after_create_commit  :notify_follow_request
  after_update_commit  :notify_follow_accepted, if: -> { saved_change_to_status?(from: "pending", to: "accepted") }

  scope :pending,  -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }

  def accept!
    update!(status: "accepted", accepted_at: Time.current)
  end

  private

  def cannot_follow_self
    errors.add(:follower_id, "can't follow yourself") if follower_id == following_id
  end

  def notify_follow_request
    Notification.create!(
      recipient: following,
      actor:     follower,
      notifiable: self,
      action:    "follow_request"
    )
  end

  def notify_follow_accepted
    Notification.create!(
      recipient: follower,
      actor:     following,
      notifiable: self,
      action:    "follow_accepted"
    )
  end
end
