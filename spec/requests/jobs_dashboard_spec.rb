require "rails_helper"

RSpec.describe "Jobs dashboard" do
  describe "GET /jobs" do
    it "returns a successful response when signed in" do
      get "/jobs"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<section class="section">')
      expect(response.body).to include('<div class="container">')
    end

    it "redirects to the login page when signed out", :signed_out do
      login_url = new_session_url # before the request: afterwards url helpers carry the engine's /jobs script name
      get "/jobs"

      expect(response).to redirect_to(login_url)
    end

    it "does not ask for HTTP basic auth", :signed_out do
      get "/jobs"

      expect(response).not_to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to be_nil
    end
  end
end
