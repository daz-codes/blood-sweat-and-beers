require "test_helper"

class WorkoutLikeTest < ActiveSupport::TestCase
  test "belongs to user and workout" do
    like = workout_likes(:one_likes_hyrox)
    assert_equal users(:one), like.user
    assert_equal workouts(:hyrox_session), like.workout
  end

  test "creates notification for workout owner" do
    workout = workouts(:hyrox_session)
    liker = users(:two)

    assert_difference "Notification.count", 1 do
      WorkoutLike.create!(user: liker, workout: workout)
    end
  end

  test "does not notify when owner likes own workout" do
    workout = workouts(:hyrox_session)

    assert_no_difference "Notification.count" do
      WorkoutLike.create!(user: workout.user, workout: workout)
    end
  end
end
