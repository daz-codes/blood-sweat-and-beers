class AddProfileFieldsToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :username, :string
    add_column :users, :display_name, :string
    add_index :users, :username, unique: true
  end
end
