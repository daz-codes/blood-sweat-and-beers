class GenerateDailyChallengeJob < ApplicationJob
  queue_as :default

  def perform
    DailyChallengeGenerator.call
  rescue => e
    Rails.logger.error "GenerateDailyChallengeJob failed: #{e.class}: #{e.message}"
  end
end
