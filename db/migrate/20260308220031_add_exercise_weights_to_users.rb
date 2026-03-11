class AddExerciseWeightsToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :exercise_weights, :json, default: {}, null: false
  end
end
