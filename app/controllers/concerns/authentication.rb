module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    # Engines (Mission Control, Monitoring) are isolated, so their requests need the main app's URL helpers.
    # Only a plain HTML page load is remembered: a POST can't be replayed by a redirect, and a JSON fetch or a
    # Turbo frame poll (the experiments status_frame) would overwrite the page the user actually asked for.
    def request_authentication
      session[:return_to_after_authenticating] = request.url if request.get? && request.format.html? && !turbo_frame_request?
      redirect_to main_app.new_session_url
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || main_app.root_url
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
