class Workout < ApplicationRecord
  include Workout::Status
  include Workout::Likeable
  include Workout::StructureBuilder

  belongs_to :user
  belongs_to :source_workout, class_name: "Workout", optional: true
  belongs_to :activity, optional: true
  has_many :workout_logs, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  DIFFICULTIES = %w[beginner intermediate advanced].freeze
  FORMATS     = %w[straight rounds amrap emom tabata for_time ladder mountain matrix hundred].freeze

  def self.valid_formats = FORMATS

  validates :difficulty, inclusion: { in: DIFFICULTIES }
  validates :duration_mins, numericality: { greater_than: 0 }

  def activity_slug
    activity&.slug
  end

  def activity_name
    activity&.name
  end

  def discover_videos_later
    DiscoverExerciseVideosJob.perform_later(id)
  end
end
