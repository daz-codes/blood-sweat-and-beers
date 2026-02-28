class AddNameToWorkouts < ActiveRecord::Migration[8.2]
  def change
    add_column :workouts, :name, :string
  end
end
