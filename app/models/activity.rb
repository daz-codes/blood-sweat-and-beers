class Activity < ApplicationRecord
  has_many :workouts
  has_many :programs

  validates :name, presence: true, uniqueness: true

  def slug
    name.parameterize
  end
end
