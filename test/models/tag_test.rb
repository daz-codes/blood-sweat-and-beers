require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "validates name presence" do
    tag = Tag.new(name: nil)
    assert_not tag.valid?
    assert_includes tag.errors[:name], "can't be blank"
  end

  test "auto-generates slug from name" do
    tag = Tag.new(name: "Hyrox Manchester 2026")
    tag.valid?
    assert_equal "hyrox-manchester-2026", tag.slug
  end

  test "validates slug uniqueness" do
    Tag.create!(name: "Unique Tag")
    duplicate = Tag.new(name: "Unique Tag")
    assert_not duplicate.valid?
  end
end
