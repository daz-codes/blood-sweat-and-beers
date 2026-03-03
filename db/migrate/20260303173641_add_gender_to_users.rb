class AddGenderToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :gender, :string
  end
end
