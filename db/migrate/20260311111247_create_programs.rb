class CreatePrograms < ActiveRecord::Migration[8.2]
  def change
    create_table :programs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tag,  null: false, foreign_key: true
      t.string  :name,              null: false
      t.integer :weeks_count,       null: false
      t.integer :sessions_per_week, null: false
      t.integer :duration_mins,     null: false
      t.string  :difficulty,        null: false, default: "intermediate"
      t.string  :status,            null: false, default: "pending"

      t.timestamps
    end

    add_index :programs, [ :user_id, :created_at ]
  end
end
