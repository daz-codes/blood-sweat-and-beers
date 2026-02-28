class CreateComments < ActiveRecord::Migration[8.2]
  def change
    create_table :comments do |t|
      t.references :user,        null: false, foreign_key: true
      t.references :workout_log, null: false, foreign_key: true
      t.text       :body,        null: false

      t.timestamps
    end

    add_index :comments, [ :workout_log_id, :created_at ]

    add_column :workout_logs, :comments_count, :integer, null: false, default: 0
  end
end
