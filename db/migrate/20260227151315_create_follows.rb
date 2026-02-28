class CreateFollows < ActiveRecord::Migration[8.2]
  def change
    create_table :follows do |t|
      t.references :follower,  null: false, foreign_key: { to_table: :users }
      t.references :following, null: false, foreign_key: { to_table: :users }
      t.string     :status,    null: false, default: "pending"
      t.datetime   :requested_at, null: false
      t.datetime   :accepted_at

      t.timestamps
    end

    add_index :follows, [ :follower_id, :following_id ], unique: true
    add_index :follows, [ :following_id, :status ]
    add_index :follows, [ :follower_id, :status ]
  end
end
