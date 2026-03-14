class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection only: :create

  def create
    auth = request.env["omniauth.auth"]
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid)

    if identity
      # Existing OAuth identity — sign in
      start_new_session_for identity.user
      redirect_to after_authentication_url, notice: "Signed in with #{provider_name(auth.provider)}."
    elsif Current.user
      # Logged-in user linking a new provider
      Current.user.identities.create!(provider: auth.provider, uid: auth.uid)
      redirect_to edit_profile_path, notice: "#{provider_name(auth.provider)} account linked."
    else
      # New user or existing user matching by email
      user = User.find_by(email_address: auth.info.email)

      if user
        # Link OAuth to existing email-matched account
        user.identities.create!(provider: auth.provider, uid: auth.uid)
      else
        # Create brand new user (no password needed)
        user = User.new(
          email_address: auth.info.email,
          display_name: auth.info.name
        )
        user.skip_password_validation = true
        user.save!
        user.identities.create!(provider: auth.provider, uid: auth.uid)
      end

      start_new_session_for user
      redirect_to after_authentication_url, notice: "Signed in with #{provider_name(auth.provider)}."
    end
  end

  def failure
    redirect_to sign_in_path, alert: "Authentication failed: #{params[:message].to_s.humanize}."
  end

  private

  def provider_name(provider)
    {
      "google_oauth2" => "Google",
      "apple" => "Apple",
      "facebook" => "Facebook"
    }.fetch(provider, provider.titleize)
  end
end
