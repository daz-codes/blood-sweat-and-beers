require "test_helper"

class WorkoutTest < ActiveSupport::TestCase
  test "validates difficulty inclusion" do
    workout = Workout.new(difficulty: "impossible", duration_mins: 60, user: users(:one))
    assert_not workout.valid?
  end

  test "validates duration_mins is positive" do
    workout = Workout.new(difficulty: "intermediate", duration_mins: 0, user: users(:one))
    assert_not workout.valid?
  end

  test "activity_name delegates to activity" do
    workout = workouts(:hyrox_session)
    assert_equal "Hyrox", workout.activity_name
  end

  test "activity_name returns nil without activity" do
    workout = Workout.new(user: users(:one), difficulty: "intermediate", duration_mins: 60)
    assert_nil workout.activity_name
  end

  test "activity_slug parameterizes activity name" do
    workout = workouts(:hyrox_session)
    assert_equal "hyrox", workout.activity_slug
  end

  test "most_liked_with_activity returns workouts ordered by likes" do
    hyrox = activities(:hyrox)
    results = Workout.most_liked_with_activity(hyrox, limit: 5)
    assert_includes results, workouts(:hyrox_session)
  end

  test "most_liked_with_activity accepts string name" do
    results = Workout.most_liked_with_activity("Hyrox", limit: 5)
    assert_includes results, workouts(:hyrox_session)
  end

  test "active scope returns active workouts" do
    assert_includes Workout.active, workouts(:hyrox_session)
    assert_not_includes Workout.active, workouts(:template_workout)
  end

  test "templates scope returns template workouts" do
    assert_includes Workout.templates, workouts(:template_workout)
    assert_not_includes Workout.templates, workouts(:hyrox_session)
  end
end
