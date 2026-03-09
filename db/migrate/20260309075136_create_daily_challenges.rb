class CreateDailyChallenges < ActiveRecord::Migration[8.0]
  def change
    create_table :daily_challenges do |t|
      t.date :date, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.string :scoring_type, null: false

      t.timestamps
    end

    add_index :daily_challenges, :date, unique: true
  end
end
