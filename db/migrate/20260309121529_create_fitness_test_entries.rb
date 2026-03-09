class CreateFitnessTestEntries < ActiveRecord::Migration[8.2]
  def change
    create_table :fitness_test_entries do |t|
      t.references :user,     null: false, foreign_key: true
      t.string     :test_key, null: false
      t.decimal    :value,    null: false, precision: 12, scale: 3
      t.date       :recorded_on, null: false

      t.timestamps
    end

    add_index :fitness_test_entries, [ :user_id, :test_key, :recorded_on ]
  end
end
