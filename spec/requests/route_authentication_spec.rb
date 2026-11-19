require "rails_helper"

# Default deny, proven by walking every route the app serves, including the mounted engines:
# a signed out request to any of them must be sent to the login page.
RSpec.describe "Route authentication", :signed_out do
  def return_to
    session[:return_to_after_authenticating]
  end

  # Taken before the request: afterwards url helpers carry the last controller's script name (/jobs, /monitoring).
  let!(:login_url) { new_session_url }

  it "walks the app routes and both mounted engines" do
    paths = RouteWalk.walked.pluck(:path)

    expect(paths).to include("/interviews", "/orchestration/pipelines", "/monitoring/events", "/jobs/applications/x/queues")
    expect(paths.size).to be > 100
  end

  it "has no route with a blank verb, which the walk would silently skip" do
    expect(RouteWalk.entries.select { |entry| entry[:verb].blank? }).to be_empty
  end

  it "has no mounted Rack app that the walk does not cover" do
    expect(RouteWalk.uncovered_mounts).to be_empty
  end

  it "mounts only the engines this walk knows about" do
    expect(RouteWalk.mount_prefixes).to match_array(%w[/monitoring /jobs])
  end

  it "leaves only the health check and the login actions open" do
    expect(RouteWalk.open_entries.pluck(:path)).to match_array(%w[/up /session/new /session])
  end

  it "serves the health check without a login" do
    get "/up"

    expect(response).to be_successful
  end

  RouteWalk.walked.each do |entry|
    it "sends signed out #{entry[:verb]} #{entry[:path]} (#{entry[:action]}) to the login page" do
      public_send(entry[:verb].downcase, entry[:path])

      expect(response).to redirect_to(login_url)
    end

    next if entry[:verb] == "GET"

    it "does not remember signed out #{entry[:verb]} #{entry[:path]} as a return-to" do
      public_send(entry[:verb].downcase, entry[:path])

      expect(return_to).to be_nil
    end
  end
end
