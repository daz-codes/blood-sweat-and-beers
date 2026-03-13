class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :source_workout, class_name: "Workout", optional: true
  belongs_to :activity, optional: true
  has_many :workout_logs, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings
  has_many :workout_likes, dependent: :destroy

  after_save :record_exercise_weights, if: -> { saved_change_to_status?(to: "active") }

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

  private

  def record_exercise_weights
    ExerciseWeightRecorder.call(user, structure)
  end
end
