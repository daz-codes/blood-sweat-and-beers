class ChallengeEntry < ApplicationRecord
  belongs_to :user
  belongs_to :daily_challenge

  validates :score, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :daily_challenge_id, message: "already logged this challenge" }
  validates :logged_at, presence: true

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
