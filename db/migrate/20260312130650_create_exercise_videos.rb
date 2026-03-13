class CreateExerciseVideos < ActiveRecord::Migration[8.2]
  def change
    create_table :exercise_videos do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :url, null: false
      t.boolean :verified, default: false, null: false

      t.timestamps
    end

    add_index :exercise_videos, :slug, unique: true
  end
end
