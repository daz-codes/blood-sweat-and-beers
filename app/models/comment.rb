class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :workout_log, counter_cache: true

  validates :body, presence: true, length: { maximum: 500 }

  scope :chronological, -> { order(created_at: :asc) }
end
