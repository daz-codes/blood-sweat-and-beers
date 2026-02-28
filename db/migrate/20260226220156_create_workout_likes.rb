class CreateWorkoutLikes < ActiveRecord::Migration[8.2]
  def change
    create_table :workout_likes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workout, null: false, foreign_key: true

      t.timestamps
    end
    add_index :workout_likes, [ :user_id, :workout_id ], unique: true
  end
end
