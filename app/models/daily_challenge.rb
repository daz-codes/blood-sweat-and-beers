class DailyChallenge < ApplicationRecord
  has_many :challenge_entries, dependent: :destroy

  SCORING_TYPES = %w[time reps rounds weight].freeze

  validates :scoring_type, inclusion: { in: SCORING_TYPES }
  validates :date, presence: true, uniqueness: true
  validates :title, :description, presence: true

  def self.today
    find_by(date: Date.current)
  end

  def leaderboard
    entries = challenge_entries.includes(:user)
    scoring_type == "time" ? entries.order(score: :asc) : entries.order(score: :desc)
  end

  def user_entry(user)
    challenge_entries.find_by(user: user)
  end
end
