class ChallengeEntriesController < ApplicationController
  before_action :require_authentication

  def create
    @challenge = DailyChallenge.find(params[:daily_challenge_id])

    if @challenge.challenge_entries.exists?(user: Current.user)
      redirect_to root_path, alert: "You've already logged this challenge."
      return
    end

    score = parse_score(params[:score], @challenge.scoring_type)

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

  def parse_score(raw, scoring_type)
    return nil if raw.blank?
    if scoring_type == "time" && raw.match?(/\A\d+:\d{2}\z/)
      parts = raw.split(":")
      parts[0].to_i * 60 + parts[1].to_i
    else
      raw.to_f
    end
  end
end
