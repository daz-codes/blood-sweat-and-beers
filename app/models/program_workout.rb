class ProgramWorkout < ApplicationRecord
  belongs_to :program
  belongs_to :workout, optional: true

  STATUSES = %w[pending generating complete failed].freeze
  validates :status, inclusion: { in: STATUSES }

  def pending?    = status == "pending"
  def generating? = status == "generating"
  def complete?   = status == "complete"
  def failed?     = status == "failed"

  def turbo_dom_id = "program_workout_#{id}"
end
