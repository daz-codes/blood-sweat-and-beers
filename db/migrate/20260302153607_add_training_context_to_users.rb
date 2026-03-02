class AddTrainingContextToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :age, :integer
    add_column :users, :height_cm, :integer
    add_column :users, :weight_kg, :decimal
    add_column :users, :pool_length, :string
    add_column :users, :run_preference, :string
    add_column :users, :equipment, :string, array: true, default: []
    add_column :users, :personal_bests, :jsonb, default: {}
  end
end
