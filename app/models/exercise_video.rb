class ExerciseVideo < ApplicationRecord
  validates :name, :slug, :url, presence: true
  validates :slug, uniqueness: true

  # Look up a video URL for an exercise name. Returns the URL string or nil.
  def self.url_for(exercise_name)
    slug = slugify(exercise_name)
    record = find_by(slug: slug)
    record&.url
  end

  # Normalize an exercise name into a lookup slug.
  # Strips parentheticals, notes, weight references, and common suffixes.
  def self.slugify(name)
    name.to_s
        .downcase
        .gsub(/\(.*?\)/, "")                    # remove parentheticals
        .gsub(/\d+\s*kg/, "")                   # remove weight refs
        .gsub(/\d+\s*reps?/, "")                # remove rep refs
        .gsub(/each\s+side|per\s+side|alternating/i, "")
        .gsub(/[^a-z0-9\s-]/, "")               # strip punctuation
        .strip
        .gsub(/\s+/, "-")                        # spaces to hyphens
        .gsub(/-+/, "-")                         # collapse hyphens
        .gsub(/\A-|-\z/, "")                     # trim leading/trailing hyphens
  end
end
