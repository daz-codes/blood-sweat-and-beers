class AddPlanToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :plan, :string, default: "free", null: false
  end
end
