require "net/http"

# Attempts to find a musclewiki.com URL for an exercise name.
# Tries several slug variations and verifies with an HTTP HEAD request.
# If found, persists to ExerciseVideo for future lookups.
#
# Usage:
#   ExerciseVideoLookup.call("Barbell Back Squat")
#   # => "https://musclewiki.com/exercise/barbell-squat" or nil
class ExerciseVideoLookup
  BASE_URL = "https://musclewiki.com/exercise".freeze

  EQUIPMENT_PREFIXES = %w[barbell dumbbell kettlebell bodyweight cable machine medicine-ball plate resistance-band].freeze

  def self.call(exercise_name)
    new(exercise_name).call
  end

  def initialize(exercise_name)
    @name = exercise_name.to_s.strip
  end

  def call
    return nil if @name.blank?

    slug = ExerciseVideo.slugify(@name)

    # Already known?
    existing = ExerciseVideo.find_by(slug: slug)
    return existing.url if existing

    # Generate candidate slugs to try
    candidates = build_candidates

    candidates.each do |candidate_slug|
      url = "#{BASE_URL}/#{candidate_slug}"
      if url_exists?(url)
        ExerciseVideo.create!(
          name: @name,
          slug: slug,
          url: url,
          verified: true
        )
        return url
      end
    end

    # Mark as not found so we don't keep retrying
    ExerciseVideo.create!(
      name: @name,
      slug: slug,
      url: "",
      verified: false
    )
    nil
  rescue ActiveRecord::RecordNotUnique
    # Race condition — another process created it
    ExerciseVideo.find_by(slug: ExerciseVideo.slugify(@name))&.url
  end

  private

  def build_candidates
    base = @name.downcase
                .gsub(/\(.*?\)/, "")
                .gsub(/\d+\s*kg/, "")
                .gsub(/each\s+side|per\s+side|alternating/i, "")
                .gsub(/[^a-z0-9\s-]/, "")
                .strip
                .gsub(/\s+/, "-")

    candidates = [base]

    # Try with common equipment prefixes
    EQUIPMENT_PREFIXES.each do |prefix|
      candidates << "#{prefix}-#{base}" unless base.start_with?(prefix)
    end

    # Try without equipment prefix (e.g. "barbell-back-squat" → "back-squat")
    EQUIPMENT_PREFIXES.each do |prefix|
      if base.start_with?("#{prefix}-")
        stripped = base.sub("#{prefix}-", "")
        candidates << stripped
      end
    end

    # Common abbreviation expansions
    candidates << base.gsub("db-", "dumbbell-")
    candidates << base.gsub("kb-", "kettlebell-")

    candidates.uniq
  end

  def url_exists?(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    response = http.request_head(uri.path)
    response.code.to_i == 200
  rescue StandardError
    false
  end
end
