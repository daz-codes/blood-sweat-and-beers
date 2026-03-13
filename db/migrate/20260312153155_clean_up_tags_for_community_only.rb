class CleanUpTagsForCommunityOnly < ActiveRecord::Migration[8.2]
  def up
    # Delete all main/minor tags and their taggings (keep group_code tags as community tags)
    execute <<~SQL
      DELETE FROM taggings WHERE tag_id IN (
        SELECT id FROM tags WHERE tag_type IN ('main', 'minor')
      )
    SQL
    execute <<~SQL
      DELETE FROM tags WHERE tag_type IN ('main', 'minor')
    SQL

    # Remove tag_type column — all remaining tags are community tags
    remove_column :tags, :tag_type

    # Remove tag_id from programs (replaced by activity string)
    remove_foreign_key :programs, :tags
    remove_index :programs, :tag_id
    remove_column :programs, :tag_id
  end

  def down
    add_column :tags, :tag_type, :string, null: false, default: "minor"
    add_column :programs, :tag_id, :integer
    add_index :programs, :tag_id
    add_foreign_key :programs, :tags
  end
end
