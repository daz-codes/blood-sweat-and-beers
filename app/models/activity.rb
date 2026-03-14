class Activity < ApplicationRecord
  DEFAULT_NAMES = [
    "General Fitness", "Strength Training", "Hyrox",
    "Deka", "Functional Muscle", "Functional Workout", "F45"
  ].freeze

  has_many :workouts
  has_many :programs

  validates :name, presence: true, uniqueness: true

  scope :defaults, -> { where(name: DEFAULT_NAMES) }

  def slug
    name.parameterize
  end
end
