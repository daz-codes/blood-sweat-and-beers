require "test_helper"

class FeedControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "index requires authentication" do
    sign_out
    get root_path
    assert_response :redirect
  end

  test "index renders feed" do
    get root_path
    assert_response :success
  end

  test "index with activity filter" do
    get root_path, params: { activity: "Hyrox" }
    assert_response :success
  end

  test "index with pagination" do
    get root_path, params: { page: 2 }
    assert_response :success
  end
end
