class ChallengeEntriesController < ApplicationController
  before_action :require_authentication
  rate_limit to: 10, within: 3.minutes, only: :create

  def create
    @challenge = DailyChallenge.find(params[:daily_challenge_id])

    if @challenge.challenge_entries.exists?(user: Current.user)
      redirect_to root_path, alert: "You've already logged this challenge."
      return
    end

    score = ChallengeEntry.parse_score(params[:score], @challenge.scoring_type)

    unless score&.positive?
      redirect_to root_path, alert: "Please enter a valid score."
      return
    end

    @challenge.challenge_entries.create!(
      user:       Current.user,
      score:      score,
      rx:         params[:rx] == "1",
      notes:      params[:notes].presence,
      logged_at:  Time.current
    )

    redirect_to root_path, notice: "Result logged! Nice work 💪"
  rescue => e
    Rails.logger.error "ChallengeEntriesController#create failed: #{e.message}"
    redirect_to root_path, alert: "Could not log result. Please try again."
  end

  private
end
