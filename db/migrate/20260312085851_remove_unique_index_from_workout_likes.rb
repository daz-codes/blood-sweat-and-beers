class RemoveUniqueIndexFromWorkoutLikes < ActiveRecord::Migration[8.2]
  def change
    remove_index :workout_likes, [:user_id, :workout_id], unique: true
    add_index :workout_likes, [:user_id, :workout_id]
  end
end
