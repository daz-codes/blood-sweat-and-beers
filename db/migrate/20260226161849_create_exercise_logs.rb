class CreateExerciseLogs < ActiveRecord::Migration[8.2]
  def change
    create_table :exercise_logs do |t|
      t.references :workout_log, null: false, foreign_key: true
      t.references :exercise, null: true, foreign_key: true  # nil for run steps
      t.integer :step_order, null: false
      t.jsonb :sets_data, null: false, default: []

      t.timestamps
    end

    add_index :exercise_logs, :step_order
    add_index :exercise_logs, :sets_data, using: :gin
  end
end
