class CreateGenerationUses < ActiveRecord::Migration[8.2]
  def change
    create_table :generation_uses do |t|
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :generation_uses, [ :user_id, :created_at ]
  end
end
