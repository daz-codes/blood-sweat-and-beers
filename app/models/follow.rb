class Follow < ApplicationRecord
  belongs_to :follower,  class_name: "User"
  belongs_to :following, class_name: "User"

  validates :follower_id, uniqueness: { scope: :following_id }
  validate  :cannot_follow_self

  before_create { self.requested_at = Time.current }

  scope :pending,  -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }

  def accept!
    update!(status: "accepted", accepted_at: Time.current)
  end

  private

  def cannot_follow_self
    errors.add(:follower_id, "can't follow yourself") if follower_id == following_id
  end
end
