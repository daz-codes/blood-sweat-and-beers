class FitnessTestEntry < ApplicationRecord
  belongs_to :user

  validates :test_key,    inclusion: { in: FitnessTests::ALL_KEYS }
  validates :value,       numericality: { greater_than: 0 }
  validates :recorded_on, presence: true

  scope :for_test,   ->(key) { where(test_key: key) }
  scope :chronological, -> { order(recorded_on: :asc) }

  # Parse "3:45" → 225, "1:03:45" → 3825, "225" → 225 for time; otherwise float
  def self.parse_value(raw, unit)
    raw = raw.to_s.strip
    return nil if raw.blank?

    if unit == "time"
      case raw
      when /\A(\d+):(\d{2}):(\d{2})\z/
        $1.to_i * 3600 + $2.to_i * 60 + $3.to_i
      when /\A(\d+):(\d{2})\z/
        $1.to_i * 60 + $2.to_i
      when /\A\d+(\.\d+)?\z/
        raw.to_f
      end
    else
      v = raw.to_f
      v > 0 ? v : nil
    end
  end

  def self.input_hint(unit)
    unit == "time" ? "enter time as mm:ss or h:mm:ss" : "enter a number"
  end
end
