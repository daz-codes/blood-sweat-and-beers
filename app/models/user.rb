class User < ApplicationRecord
  FREE_GENERATION_LIMIT = 5

  include User::GenerationQuota
  include User::FollowGraph

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
  has_many :fitness_test_entries, dependent: :destroy
  has_many :notifications, foreign_key: :recipient_id, dependent: :delete_all

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

  def display
    display_name.presence || username.presence || email_address.split("@").first
  end

  def initials
    display.first(1).upcase
  end

  # Record exercise weights from a workout structure into the user's profile
  def record_weights_from_workout(structure)
    return unless structure.is_a?(Hash)

    updates = {}
    Array(structure["sections"]).each do |section|
      Array(section["exercises"]).each do |exercise|
        name = exercise["name"].to_s.strip
        kg   = exercise["weight_kg"]
        next if name.blank? || kg.blank? || kg.to_f <= 0
        normalized = name.downcase.gsub(/[^a-z0-9\s]/, "").strip.gsub(/\s+/, "_")
        updates[normalized] = kg.to_f
      end
    end

    return if updates.empty?
    update_column(:exercise_weights, (exercise_weights || {}).merge(updates))
  end
end
