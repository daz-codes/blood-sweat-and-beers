class Exercise < ApplicationRecord
  validates :name, presence: true
  validates :movement_type, presence: true
  validates :metric, inclusion: { in: %w[reps time distance] }

  scope :hyrox, -> { where("EXISTS (SELECT 1 FROM json_each(format_tags) WHERE json_each.value = 'hyrox')") }
  scope :deka, -> { where("EXISTS (SELECT 1 FROM json_each(format_tags) WHERE json_each.value = 'deka')") }
  scope :hyrox_stations, -> { hyrox.where.not(hyrox_station_order: nil).order(:hyrox_station_order) }
  scope :deka_stations, -> { deka.where.not(deka_station_order: nil).order(:deka_station_order) }
end
