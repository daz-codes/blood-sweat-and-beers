class CreateWorkouts < ActiveRecord::Migration[8.2]
  def change
    create_table :workouts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :workout_type, null: false          # "hyrox", "deka"
      t.integer :duration_mins, null: false
      t.string :difficulty, null: false, default: "intermediate"  # "beginner", "intermediate", "advanced"
      t.string :status, null: false, default: "active"            # "active", "template", "queued"
      t.jsonb :structure, null: false, default: []                # array of station/exercise objects
      t.references :source_workout, foreign_key: { to_table: :workouts }, null: true

      t.timestamps
    end

    add_index :workouts, :workout_type
    add_index :workouts, :status
    add_index :workouts, :structure, using: :gin
  end
end
