class User < ApplicationRecord
  validates :email_address, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true,
            format: { with: /\A[a-zA-Z0-9_]{3,30}\z/,
                      message: "must be 3–30 characters: letters, numbers, and underscores only" }
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :workouts, dependent: :destroy
  has_many :workout_logs, dependent: :destroy

  has_many :follows_as_follower,  class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
  has_many :follows_as_following, class_name: "Follow", foreign_key: :following_id, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :username, with: ->(u) { u.presence }  # treat blank as nil

  def display
    display_name.presence || username.presence || email_address.split("@").first
  end

  def initials
    display.first(1).upcase
  end

  # IDs of users this user is accepted-following (for feed query)
  def accepted_following_ids
    follows_as_follower.accepted.pluck(:following_id)
  end

  # Count of pending inbound follow requests
  def pending_follow_request_count
    follows_as_following.pending.count
  end

  # Follow state this user has toward another user
  def follow_state_for(other_user)
    return :self if id == other_user.id
    follow = follows_as_follower.find_by(following_id: other_user.id)
    return :none unless follow
    follow.status.to_sym
  end
end
