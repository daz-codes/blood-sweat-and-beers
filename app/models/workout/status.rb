module Workout::Status
  extend ActiveSupport::Concern

  included do
    STATUSES = %w[active template queued preview].freeze

    validates :status, inclusion: { in: STATUSES }

    scope :templates, -> { where(status: "template") }
    scope :active, -> { where(status: "active") }
    scope :queued, -> { where(status: "queued") }

    after_save_commit :record_exercise_weights, if: -> { saved_change_to_status?(to: "active") }
  end

  private

  def record_exercise_weights
    user.record_weights_from_workout(structure)
  end
end
