class User < ApplicationRecord
  FREE_GENERATION_LIMIT = 5

  validates :email_address, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true,
            format: { with: /\A[a-zA-Z0-9_]{3,30}\z/,
                      message: "must be 3–30 characters: letters, numbers, and underscores only" }
  has_secure_password validations: false
  validates :password, presence: true, length: { minimum: 8 }, unless: :skip_password_validation?
  validates :password, length: { minimum: 8 }, allow_nil: true, if: :skip_password_validation?

  attr_accessor :skip_password_validation
  has_many :identities, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :workouts, dependent: :destroy
  has_many :workout_logs, dependent: :destroy
  has_many :generation_uses, dependent: :destroy
  has_many :programs, dependent: :destroy
  has_many :fitness_test_entries, dependent: :destroy
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy

  has_many :follows_as_follower,  class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
  has_many :follows_as_following, class_name: "Follow", foreign_key: :following_id, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :username, with: ->(u) { u.presence }  # treat blank as nil

  def completed_benchmark_keys
    fitness_test_entries.where(test_key: FitnessTests::BENCHMARK_KEYS).distinct.pluck(:test_key).to_set
  end

  def benchmarks_complete?
    completed_benchmark_keys.size >= FitnessTests::BENCHMARK_KEYS.size
  end

  def unread_notification_count
    notifications.unread.count
  end

  def pro?
    plan == "pro"
  end

  def free?
    plan == "free"
  end

  def generations_this_week
    generation_uses.where(created_at: 1.week.ago..).count
  end

  def generation_limit_reached?
    free? && generations_this_week >= FREE_GENERATION_LIMIT
  end

  def generations_remaining
    return nil if pro?
    [ FREE_GENERATION_LIMIT - generations_this_week, 0 ].max
  end

  def display
    display_name.presence || username.presence || email_address.split("@").first
  end

  def initials
    display.first(1).upcase
  end

  def oauth_user?
    identities.any?
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

  private

  def skip_password_validation?
    skip_password_validation || (persisted? && password_digest.present?)
  end
end
