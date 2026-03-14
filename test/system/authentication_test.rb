require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "sign in and see the feed" do
    visit new_session_path

    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"

    assert_current_path root_path
  end

  test "sign in with wrong password" do
    visit new_session_path

    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "wrong"
    click_on "Sign in"

    assert_current_path new_session_path
  end
end
