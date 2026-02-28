class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :source_workout, class_name: "Workout", optional: true
  has_many :workout_logs, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings
  has_many :workout_likes, dependent: :destroy

  TYPES       = %w[hyrox deka custom].freeze
  DIFFICULTIES = %w[beginner intermediate advanced].freeze
  STATUSES    = %w[active template queued].freeze
  FORMATS     = %w[straight rounds amrap emom tabata].freeze

  def self.valid_formats = FORMATS

  validates :workout_type, inclusion: { in: TYPES }
  validates :difficulty, inclusion: { in: DIFFICULTIES }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_mins, numericality: { greater_than: 0 }

  scope :templates, -> { where(status: "template") }
  scope :active, -> { where(status: "active") }
  scope :queued, -> { where(status: "queued") }

  def self.most_liked_with_tags(tag_ids, limit: 25)
    joins(:taggings)
      .where(taggings: { tag_id: tag_ids })
      .left_joins(:workout_likes)
      .group(:id)
      .order(Arel.sql("COUNT(DISTINCT workout_likes.id) DESC"))
      .limit(limit)
  end
end
