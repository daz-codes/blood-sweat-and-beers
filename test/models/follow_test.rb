require "test_helper"

class FollowTest < ActiveSupport::TestCase
  test "cannot follow yourself" do
    follow = Follow.new(follower: users(:one), following: users(:one))
    assert_not follow.valid?
  end

  test "accept sets status and accepted_at" do
    follow = Follow.create!(follower: users(:two), following: users(:one))
    follow.accept!
    assert_equal "accepted", follow.status
    assert_not_nil follow.accepted_at
  end

  test "pending scope" do
    pending = Follow.create!(follower: users(:two), following: users(:one))
    assert_includes Follow.pending, pending
    assert_not_includes Follow.pending, follows(:one_follows_two)
  end

  test "accepted scope" do
    assert_includes Follow.accepted, follows(:one_follows_two)
  end

  test "validates uniqueness of follower per following" do
    duplicate = Follow.new(
      follower: follows(:one_follows_two).follower,
      following: follows(:one_follows_two).following
    )
    assert_not duplicate.valid?
  end
end
