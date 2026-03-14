Rails.application.config.middleware.use OmniAuth::Builder do
  if ENV["GOOGLE_CLIENT_ID"].present?
    provider :google_oauth2,
      ENV["GOOGLE_CLIENT_ID"],
      ENV["GOOGLE_CLIENT_SECRET"],
      scope: "email,profile"
  end

  if ENV["APPLE_CLIENT_ID"].present?
    provider :apple,
      ENV["APPLE_CLIENT_ID"],
      ENV["APPLE_TEAM_ID"],
      ENV["APPLE_KEY_ID"],
      ENV["APPLE_PRIVATE_KEY"],
      scope: "email name"
  end

  if ENV["FACEBOOK_APP_ID"].present?
    provider :facebook,
      ENV["FACEBOOK_APP_ID"],
      ENV["FACEBOOK_APP_SECRET"],
      scope: "email,public_profile"
  end
end

OmniAuth.config.allowed_request_methods = [ :post ]
