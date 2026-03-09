class CreatePersonalRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :personal_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workout_log, null: false, foreign_key: true
      t.string :exercise_name, null: false
      t.string :metric, null: false
      t.decimal :value, precision: 10, scale: 2, null: false
      t.datetime :achieved_at, null: false

      t.timestamps
    end

    add_index :personal_records, [ :user_id, :exercise_name, :metric ],
              name: "index_prs_on_user_exercise_metric"
  end
end
