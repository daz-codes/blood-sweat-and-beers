class ChallengeEntry < ApplicationRecord
  belongs_to :user
  belongs_to :daily_challenge

  validates :score, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :daily_challenge_id, message: "already logged this challenge" }
  validates :logged_at, presence: true

  def self.parse_score(raw, scoring_type)
    return nil if raw.blank?
    if scoring_type == "time" && raw.match?(/\A\d+:\d{2}\z/)
      parts = raw.split(":")
      parts[0].to_i * 60 + parts[1].to_i
    else
      raw.to_f
    end
  end

  after_create_commit :broadcast_leaderboard_update

  private

  def broadcast_leaderboard_update
    broadcast_replace_to(
      "challenge_#{daily_challenge_id}_leaderboard",
      target: "challenge_leaderboard_#{daily_challenge_id}",
      partial: "challenges/leaderboard",
      locals: { challenge: daily_challenge }
    )
  end
end
