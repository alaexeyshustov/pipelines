require "rails_helper"

RSpec.describe "Authentication", :signed_out do
  let(:user) { create(:user) }

  def log_in
    post session_path, params: { email_address: user.email_address, password: user.password }
  end

  def return_to
    session[:return_to_after_authenticating]
  end

  describe "default deny" do
    it "redirects a signed out GET to the login page" do
      get interviews_path

      expect(response).to redirect_to(new_session_url)
    end

    it "serves the login page and the health check without a session" do
      get new_session_path
      expect(response).to be_successful

      get rails_health_check_path
      expect(response).to be_successful
    end

    it "serves the app once signed in" do
      log_in

      get interviews_path

      expect(response).to be_successful
    end
  end

  describe "return to" do
    it "sends a GET back to where it was headed after login" do
      get interviews_path
      expect(return_to).to end_with(interviews_path)

      log_in

      expect(response).to redirect_to(interviews_url)
    end

    it "keeps the query string" do
      get interviews_path(q: "ruby")

      log_in

      expect(response).to redirect_to(interviews_url(q: "ruby"))
    end

    it "lands on the dashboard when nothing was requested first" do
      log_in

      expect(response).to redirect_to(root_url)
    end

    it "forgets the target once it has been used" do
      get interviews_path
      log_in

      expect(return_to).to be_nil
    end

    it "does not store a POST" do
      post batch_interviews_path

      expect(response).to redirect_to(new_session_url)
      expect(return_to).to be_nil

      log_in

      expect(response).to redirect_to(root_url)
    end

    it "does not store a DELETE" do
      delete interview_path(1)

      expect(return_to).to be_nil
    end

    it "does not store a Turbo frame request" do
      get status_frame_evaluation_experiment_path(1), headers: { "Turbo-Frame" => "status" }

      expect(response).to redirect_to(new_session_url)
      expect(return_to).to be_nil

      log_in

      expect(response).to redirect_to(root_url)
    end

    it "does not let a JSON fetch overwrite the stored target" do
      get interviews_path
      get prompt_versions_evaluation_experiments_path(agent_name: "x"), headers: { "Accept" => "application/json" }

      expect(response).to redirect_to(new_session_url)

      log_in

      expect(response).to redirect_to(interviews_url)
    end

    it "does not let a Turbo frame poll overwrite the stored target" do
      get interviews_path
      get status_frame_evaluation_experiment_path(1), headers: { "Turbo-Frame" => "status" }

      log_in

      expect(response).to redirect_to(interviews_url)
    end
  end
end
