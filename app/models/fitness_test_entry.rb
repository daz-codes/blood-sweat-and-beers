class FitnessTestEntry < ApplicationRecord
  belongs_to :user

  validates :test_key,    inclusion: { in: FitnessTests::ALL_KEYS }
  validates :value,       numericality: { greater_than: 0 }
  validates :recorded_on, presence: true

  scope :for_test,   ->(key) { where(test_key: key) }
  scope :chronological, -> { order(recorded_on: :asc) }
end
