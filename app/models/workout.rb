class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :source_workout, class_name: "Workout", optional: true
  belongs_to :activity, optional: true
  has_many :workout_logs, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings
  has_many :workout_likes, dependent: :destroy

  after_save_commit :record_exercise_weights, if: -> { saved_change_to_status?(to: "active") }

  DIFFICULTIES = %w[beginner intermediate advanced].freeze
  STATUSES    = %w[active template queued preview].freeze
  FORMATS     = %w[straight rounds amrap emom tabata for_time ladder mountain matrix hundred].freeze

  def self.valid_formats = FORMATS

  validates :difficulty, inclusion: { in: DIFFICULTIES }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_mins, numericality: { greater_than: 0 }

  scope :templates, -> { where(status: "template") }
  scope :active, -> { where(status: "active") }
  scope :queued, -> { where(status: "queued") }

  def activity_slug
    activity&.slug
  end

  def activity_name
    activity&.name
  end

  def self.most_liked_with_activity(activity, limit: 25)
    scope = if activity.is_a?(Activity)
      where(activity: activity)
    else
      joins(:activity).where(activities: { name: activity })
    end
    scope.left_joins(:workout_likes)
         .group(:id)
         .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
         .limit(limit)
  end

  def discover_videos_later
    DiscoverExerciseVideosJob.perform_later(id)
  end

  # Build structure JSON from nested controller params
  def self.structure_from_params(sections_param)
    return { "sections" => [] } unless sections_param.present?

    sections = sections_param.to_unsafe_h
                             .sort_by { |k, _| k.to_i }
                             .map { |_, s| build_section_from_params(s) }
                             .reject { |s| s["name"].blank? }

    { "sections" => sections }
  end

  def self.build_section_from_params(s)
    section = {
      "name"   => s[:name].to_s.strip,
      "format" => valid_formats.include?(s[:format]) ? s[:format] : "straight"
    }
    section["rounds"]        = s[:rounds].to_i        if s[:rounds].present?
    section["duration_mins"] = s[:duration_mins].to_i if s[:duration_mins].present?
    section["rest_secs"]     = s[:rest_secs].to_i     if s[:rest_secs].present?
    section["notes"]         = s[:notes].to_s.strip   if s[:notes].present?

    if %w[ladder mountain].include?(section["format"])
      section["varies"] = s[:varies].to_s if s[:varies].present?
      %w[start end step].each do |key|
        next unless s[key.to_sym].present?
        val = s[key.to_sym].to_f
        section[key] = val == val.to_i ? val.to_i : val
      end
      if section["format"] == "mountain" && s[:peak].present?
        val = s[:peak].to_f
        section["peak"] = val == val.to_i ? val.to_i : val
      end
      section["rest_between_rungs"] = s[:rest_between_rungs].to_i if s[:rest_between_rungs].present?
    end

    if s[:exercises].present?
      section["exercises"] = s[:exercises].sort_by { |k, _| k.to_i }
                                          .map { |_, e| build_exercise_from_params(e) }
                                          .reject { |e| e["name"].blank? }
    end

    section
  end

  def self.build_exercise_from_params(e)
    ex = { "name" => e[:name].to_s.strip }
    ex["notes"]      = e[:notes].to_s.strip if e[:notes].present?
    ex["reps"]       = e[:reps].to_i        if e[:reps].present?
    ex["calories"]   = e[:calories].to_i    if e[:calories].present?
    ex["distance_m"] = e[:distance_m].to_i  if e[:distance_m].present?
    if e[:duration_m].present? || e[:duration_s_part].present?
      total_s = e[:duration_m].to_i * 60 + e[:duration_s_part].to_i
      ex["duration_s"] = total_s if total_s > 0
    end
    ex["weight_kg"]  = e[:weight_kg].to_f   if e[:weight_kg].present?
    ex
  end

  private

  def record_exercise_weights
    user.record_weights_from_workout(structure)
  end
end
