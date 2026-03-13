require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "validates name presence" do
    activity = Activity.new(name: nil)
    assert_not activity.valid?
    assert_includes activity.errors[:name], "can't be blank"
  end

  test "validates name uniqueness" do
    Activity.create!(name: "Yoga")
    duplicate = Activity.new(name: "Yoga")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "slug parameterizes the name" do
    activity = Activity.new(name: "Functional Muscle")
    assert_equal "functional-muscle", activity.slug
  end

  test "DEFAULT_NAMES contains expected activities" do
    assert_includes Activity::DEFAULT_NAMES, "General Fitness"
    assert_includes Activity::DEFAULT_NAMES, "Hyrox"
    assert_includes Activity::DEFAULT_NAMES, "F45"
    assert_equal 7, Activity::DEFAULT_NAMES.size
  end

  test "defaults scope returns only default activities" do
    defaults = Activity.defaults
    assert defaults.all? { |a| Activity::DEFAULT_NAMES.include?(a.name) }
  end

  test "find_or_create_by creates new activity" do
    assert_difference "Activity.count", 1 do
      Activity.find_or_create_by!(name: "Powerlifting")
    end
  end

  test "find_or_create_by finds existing activity" do
    existing = activities(:hyrox)
    assert_no_difference "Activity.count" do
      found = Activity.find_or_create_by!(name: "Hyrox")
      assert_equal existing.id, found.id
    end
  end
end
