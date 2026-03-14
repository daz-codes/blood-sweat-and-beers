class Comment < ApplicationRecord
  include Notifiable

  belongs_to :user
  belongs_to :workout_log, counter_cache: true, touch: true

  validates :body, presence: true, length: { maximum: 500 }

  scope :chronological, -> { order(created_at: :asc) }

  notifies action: :comment, recipient: :log_owner

  private

  def log_owner
    workout_log.user
  end
end
