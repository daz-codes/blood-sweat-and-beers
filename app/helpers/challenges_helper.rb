module ChallengesHelper
  def format_challenge_score(score, scoring_type)
    case scoring_type
    when "time"
      s = score.to_i
      "#{s / 60}:#{"%02d" % (s % 60)}"
    when "weight"
      "#{score.to_i}kg"
    when "reps"
      "#{score.to_i} reps"
    when "rounds"
      "#{score.to_i} rounds"
    end
  end
end
