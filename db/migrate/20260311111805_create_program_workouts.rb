class CreateProgramWorkouts < ActiveRecord::Migration[8.2]
  def change
    create_table :program_workouts do |t|
      t.references :program, null: false, foreign_key: true
      t.references :workout, null: true,  foreign_key: true
      t.integer :week_number,    null: false
      t.integer :session_number, null: false
      t.text    :session_notes
      t.string  :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :program_workouts, [ :program_id, :week_number, :session_number ], unique: true,
              name: "index_program_workouts_on_program_week_session"
  end
end
