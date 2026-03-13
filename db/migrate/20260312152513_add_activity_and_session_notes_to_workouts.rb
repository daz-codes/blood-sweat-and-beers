class AddActivityAndSessionNotesToWorkouts < ActiveRecord::Migration[8.2]
  def up
    # Add new columns
    add_column :workouts, :activity, :string
    add_column :workouts, :session_notes, :text
    add_column :programs, :activity, :string

    # Backfill activity from main tags
    execute <<~SQL
      UPDATE workouts
      SET activity = (
        SELECT tags.name
        FROM taggings
        JOIN tags ON tags.id = taggings.tag_id
        WHERE taggings.taggable_type = 'Workout'
          AND taggings.taggable_id = workouts.id
          AND tags.tag_type = 'main'
        LIMIT 1
      )
    SQL

    # Backfill programs.activity from their tag
    execute <<~SQL
      UPDATE programs
      SET activity = (
        SELECT tags.name
        FROM tags
        WHERE tags.id = programs.tag_id
      )
    SQL

    # Remove workout_type (always "custom", never used meaningfully)
    remove_column :workouts, :workout_type

    # Add index on activity for filtering
    add_index :workouts, :activity
  end

  def down
    add_column :workouts, :workout_type, :string, null: false, default: "custom"
    remove_index :workouts, :activity
    remove_column :workouts, :activity
    remove_column :workouts, :session_notes
    remove_column :programs, :activity
  end
end
