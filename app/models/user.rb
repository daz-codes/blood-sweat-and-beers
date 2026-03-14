class User < ApplicationRecord
  FREE_GENERATION_LIMIT = 5

  include User::Billing
  include User::GenerationQuota
  include User::FollowGraph
  include User::FitnessTracking
  include User::ExerciseWeightRecorder

  validates :email_address, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true,
            format: { with: /\A[a-zA-Z0-9_]{3,30}\z/,
                      message: "must be 3–30 characters: letters, numbers, and underscores only" }
  has_secure_password
  has_many :sessions, dependent: :delete_all
  has_many :comments, dependent: :destroy
  has_many :workouts, dependent: :destroy
  has_many :workout_logs, dependent: :destroy
  has_many :programs, dependent: :destroy
  has_many :notifications, foreign_key: :recipient_id, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :username, with: ->(u) { u.presence }

  def unread_notification_count
    notifications.unread.count
  end

  def display
    display_name.presence || username.presence || email_address.split("@").first
  end

  def initials
    display.first(1).upcase
  end
end
