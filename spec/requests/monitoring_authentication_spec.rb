require "rails_helper"

# The RubyLLM monitoring engine inherits from ActionController::Base, so the app's login is
# included into it by config/initializers/ruby_llm_monitoring.rb (GH #255).
RSpec.describe "Monitoring engine authentication" do
  it "serves the dashboard to a signed in user" do
    get "/monitoring/events"

    expect(response).to be_successful
  end

  it "sends a signed out request to the login page", :signed_out do
    login_url = new_session_url # before the request: afterwards url helpers carry the engine's script name
    get "/monitoring/events"

    expect(response).to redirect_to(login_url)
  end
end
