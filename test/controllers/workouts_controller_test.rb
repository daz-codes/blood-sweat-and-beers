require "test_helper"

class WorkoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @workout = workouts(:hyrox_session)
  end

  test "library requires authentication" do
    sign_out
    get library_path
    assert_response :redirect
  end

  test "library renders" do
    get library_path
    assert_response :success
  end

  test "library filters by activity" do
    get library_path, params: { activity: "Hyrox" }
    assert_response :success
  end

  test "show renders workout" do
    get workout_path(@workout)
    assert_response :success
  end

  test "show renders for non-owner" do
    sign_out
    sign_in_as(users(:two))
    get workout_path(@workout)
    assert_response :success
  end

  test "clone creates a copy" do
    assert_difference "Workout.count", 1 do
      post clone_workout_path(@workout)
    end
    assert_redirected_to edit_workout_path(Workout.last)
  end

  test "clone copies activity" do
    post clone_workout_path(@workout)
    cloned = Workout.last
    assert_equal @workout.activity_id, cloned.activity_id
  end

  test "destroy removes owned workout" do
    assert_difference "Workout.count", -1 do
      delete workout_path(@workout)
    end
  end
end
