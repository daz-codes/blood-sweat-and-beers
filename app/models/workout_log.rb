class WorkoutLog < ApplicationRecord
  belongs_to :user
  belongs_to :workout
  has_many :exercise_logs, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings
  has_one_attached :photo

  VISIBILITY = %w[public private].freeze

  validates :sweat_rating, numericality: { in: 1..5 }
  validates :visibility, inclusion: { in: VISIBILITY }
  validates :completed_at, presence: true

  scope :public_posts, -> { where(visibility: "public") }
  scope :recent, -> { order(completed_at: :desc) }
end
