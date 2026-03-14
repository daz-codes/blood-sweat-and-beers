require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  test "signs in existing user via identity" do
    mock_omniauth(provider: "google_oauth2", uid: "123456", email: "one@example.com", name: "User One")

    get "/auth/google_oauth2/callback"
    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "creates new user from oauth" do
    mock_omniauth(provider: "google_oauth2", uid: "brand-new-uid", email: "brand-new@example.com", name: "New User")

    assert_difference "User.count", 1 do
      assert_difference "Identity.count", 1 do
        get "/auth/google_oauth2/callback"
      end
    end

    assert_redirected_to root_path
    new_user = User.find_by(email_address: "brand-new@example.com")
    assert_equal "New User", new_user.display_name
    assert_nil new_user.password_digest
  end

  test "links identity to existing user matched by email" do
    mock_omniauth(provider: "google_oauth2", uid: "different-uid", email: "two@example.com", name: "User Two")

    assert_no_difference "User.count" do
      assert_difference "Identity.count", 1 do
        get "/auth/google_oauth2/callback"
      end
    end

    assert_redirected_to root_path
  end

  test "rejects oauth with blank email" do
    mock_omniauth(provider: "google_oauth2", uid: "no-email-uid", email: nil, name: "No Email")

    assert_no_difference [ "User.count", "Identity.count" ] do
      get "/auth/google_oauth2/callback"
    end

    assert_redirected_to sign_in_path
    assert_equal "We couldn't retrieve your email. Please sign up manually.", flash[:alert]
  end

  test "failure redirects to sign in" do
    get "/auth/failure", params: { message: "invalid_credentials" }
    assert_redirected_to sign_in_path
  end

  private

  def mock_omniauth(provider:, uid:, email:, name:)
    Rails.application.env_config["omniauth.auth"] = OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: { email: email, name: name }
    )
  end
end
