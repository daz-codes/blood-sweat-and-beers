require "test_helper"

class WorkoutLikesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @workout = workouts(:template_workout)
  end

  test "toggle requires authentication" do
    sign_out
    post like_workout_path(@workout)
    assert_response :redirect
  end

  test "toggle creates a like" do
    assert_difference "WorkoutLike.count", 1 do
      post like_workout_path(@workout), as: :turbo_stream
    end
    assert_response :success
  end

  test "toggle via html redirects" do
    post like_workout_path(@workout)
    assert_response :redirect
  end
end
