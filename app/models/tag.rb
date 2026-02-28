class Tag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  scope :used_on_workouts, -> {
    joins(:taggings).where(taggings: { taggable_type: "Workout" }).distinct.order(:name)
  }

  scope :top_used_on_workouts, ->(limit = 10) {
    joins(:taggings)
      .where(taggings: { taggable_type: "Workout" })
      .group("tags.id")
      .order("COUNT(taggings.id) DESC")
      .limit(limit)
  }

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
