class CreateActivitiesAndMigrateData < ActiveRecord::Migration[8.2]
  def up
    create_table :activities do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :activities, :name, unique: true

    # Collect all distinct activity names from workouts and programs
    names = execute("SELECT DISTINCT activity FROM workouts WHERE activity IS NOT NULL AND activity != ''").map { |r| r["activity"] }
    names += execute("SELECT DISTINCT activity FROM programs WHERE activity IS NOT NULL AND activity != ''").map { |r| r["activity"] }
    names.uniq!

    # Create activity records
    names.each do |name|
      execute "INSERT INTO activities (name, created_at, updated_at) VALUES (#{quote(name)}, datetime('now'), datetime('now'))"
    end

    # Add activity_id columns
    add_reference :workouts, :activity, foreign_key: true, index: true
    add_reference :programs, :activity, foreign_key: true, index: true

    # Backfill activity_id from activity string
    execute <<~SQL
      UPDATE workouts SET activity_id = (
        SELECT activities.id FROM activities WHERE activities.name = workouts.activity
      ) WHERE workouts.activity IS NOT NULL AND workouts.activity != ''
    SQL

    execute <<~SQL
      UPDATE programs SET activity_id = (
        SELECT activities.id FROM activities WHERE activities.name = programs.activity
      ) WHERE programs.activity IS NOT NULL AND programs.activity != ''
    SQL

    # Drop old string columns
    remove_index :workouts, :activity
    remove_column :workouts, :activity
    remove_column :programs, :activity
  end

  def down
    add_column :workouts, :activity, :string
    add_column :programs, :activity, :string
    add_index :workouts, :activity

    execute <<~SQL
      UPDATE workouts SET activity = (
        SELECT activities.name FROM activities WHERE activities.id = workouts.activity_id
      ) WHERE workouts.activity_id IS NOT NULL
    SQL

    execute <<~SQL
      UPDATE programs SET activity = (
        SELECT activities.name FROM activities WHERE activities.id = programs.activity_id
      ) WHERE programs.activity_id IS NOT NULL
    SQL

    remove_reference :workouts, :activity
    remove_reference :programs, :activity
    drop_table :activities
  end
end
