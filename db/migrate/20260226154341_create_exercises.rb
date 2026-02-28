class CreateExercises < ActiveRecord::Migration[8.2]
  def change
    create_table :exercises do |t|
      t.string :name, null: false
      t.string :movement_type, null: false        # e.g. "cardio", "strength", "functional"
      t.string :equipment                          # e.g. "sled", "ski_erg", "barbell"
      t.string :metric, null: false, default: "reps"  # "reps", "time", "distance"
      t.string :format_tags, array: true, default: []  # ["hyrox"], ["deka"], ["hyrox","deka"]
      t.integer :hyrox_station_order               # 1-8 if part of fixed Hyrox order, nil otherwise
      t.integer :deka_station_order                # 1-10 if part of fixed Deka order, nil otherwise
      t.jsonb :defaults, default: {}               # default sets/reps/distance/rest for generator
      t.timestamps
    end
  end
end
