class CreateWorkoutLogs < ActiveRecord::Migration[8.2]
  def change
    create_table :workout_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workout, null: false, foreign_key: true
      t.datetime :completed_at, null: false
      t.integer :sweat_rating, null: false
      t.text :notes
      t.string :location
      t.string :visibility, null: false, default: "public"

      t.timestamps
    end

    add_index :workout_logs, :completed_at
    add_index :workout_logs, :visibility
  end
end
