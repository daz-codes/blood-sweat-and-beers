class CreateChallengeEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :challenge_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :daily_challenge, null: false, foreign_key: true
      t.decimal :score, precision: 10, scale: 2, null: false
      t.boolean :rx, default: true, null: false
      t.text :notes
      t.datetime :logged_at, null: false

      t.timestamps
    end

    add_index :challenge_entries, [ :user_id, :daily_challenge_id ], unique: true
  end
end
