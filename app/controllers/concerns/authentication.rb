module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :link_to_sign_in_or_out, :show_user_if_signed_in
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  
def link_to_sign_in_or_out
  if authenticated?
    # Return the form as a string
    "<form class=\"button_to\" action=\"#{sign_out_path}\" accept-charset=\"UTF-8\" method=\"post\">
      <input type=\"hidden\" name=\"_method\" value=\"delete\" autocomplete=\"off\" />
      <button type=\"submit\">Sign Out</button>
      <input type=\"hidden\" name=\"authenticity_token\" value=\"#{form_authenticity_token}\" autocomplete=\"off\" />
    </form>".html_safe
  else
    "<a href=\"#{sign_in_path}\">Sign In</a>".html_safe
  end
end 

def show_user_if_signed_in
  if authenticated?
    "Signed in as #{Current.user.email_address}"
  end
end

private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
