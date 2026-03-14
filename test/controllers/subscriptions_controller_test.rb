require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "upgrade changes plan to pro" do
    assert_equal "free", @user.plan
    patch upgrade_subscription_path
    assert_redirected_to profile_path
    assert_equal "pro", @user.reload.plan
  end

  test "downgrade changes plan to free" do
    @user.update!(plan: "pro")
    patch downgrade_subscription_path
    assert_redirected_to profile_path
    assert_equal "free", @user.reload.plan
  end
end
