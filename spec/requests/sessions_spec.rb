require "rails_helper"

RSpec.describe "Sessions", :signed_out do
  let(:user) { create(:user, email_address: "admin@example.com", password: "s3cret-passw0rd") }

  def log_in(password: user.password, email_address: user.email_address)
    post session_path, params: { email_address:, password: }
  end

  describe "GET /session/new" do
    let(:doc) { Nokogiri::HTML(response.body) }

    before { get new_session_path }

    it "renders the login form" do
      expect(response).to be_successful
      expect(doc.at_css("form[action='#{session_path}'] input[name='email_address']")).to be_present
      expect(doc.at_css("form[action='#{session_path}'] input[name='password']")).to be_present
    end

    it "has no sidebar" do
      expect(doc.at_css("[data-testid='sidebar']")).to be_nil
    end
  end

  describe "POST /session" do
    it "records a session for the user" do
      expect { log_in }.to change(Session, :count).by(1)

      expect(Session.last).to have_attributes(user:)
    end

    it "sets the session cookie and lands on the dashboard" do
      log_in

      expect(response).to redirect_to(root_url)
      expect(cookies[:session_id]).to be_present
    end

    it "records the client's user agent and address on the session" do
      post session_path, params: { email_address: user.email_address, password: user.password },
                         headers: { "User-Agent" => "RSpec Browser/1.0" }

      expect(Session.last).to have_attributes(user_agent: "RSpec Browser/1.0", ip_address: "127.0.0.1")
    end

    it "lets a logged in user reach the app" do
      log_in

      get interviews_path

      expect(response).to be_successful
    end

    it "accepts the email in another case" do
      log_in(email_address: " ADMIN@Example.com ")

      expect(response).to redirect_to(root_url)
      expect(cookies[:session_id]).to be_present
    end

    it "redirects a wrong password back to the login page with an alert" do
      expect { log_in(password: "wrong") }.not_to change(Session, :count)

      expect(response).to redirect_to(new_session_url)
      expect(flash[:alert]).to be_present
    end

    it "sets no session cookie for a wrong password" do
      log_in(password: "wrong")

      expect(cookies[:session_id]).to be_blank
    end

    it "treats an unknown email like a wrong password" do
      user
      log_in(email_address: "nobody@example.com")

      expect(response).to redirect_to(new_session_url)
      expect(flash[:alert]).to be_present
    end

    describe "with a malformed body" do
      let(:alert) { "Try another email address or password." }

      before { user }

      it "redirects with the wrong-password alert when the password key is missing" do
        post session_path, params: { email_address: user.email_address }

        expect(response).to redirect_to(new_session_url)
        expect(flash[:alert]).to eq(alert)
      end

      it "redirects with the wrong-password alert when the email_address key is missing" do
        post session_path, params: { password: user.password }

        expect(response).to redirect_to(new_session_url)
        expect(flash[:alert]).to eq(alert)
      end

      it "redirects with the wrong-password alert when email_address is an array" do
        post session_path, params: { email_address: [ user.email_address ], password: user.password }

        expect(response).to redirect_to(new_session_url)
        expect(flash[:alert]).to eq(alert)
      end

      it "starts no session for a malformed body" do
        expect { post session_path, params: { password: user.password } }.not_to change(Session, :count)
      end
    end

    it "shows the alert on the login page" do
      log_in(password: "wrong")
      follow_redirect!

      expect(response.body).to include(flash[:alert])
    end

    it "does not authenticate a request that is still logged out after a failed attempt" do
      log_in(password: "wrong")

      get root_path

      expect(response).to redirect_to(new_session_url)
    end

    # The examples replay the login many times in one example; in production each attempt is its own request.
    describe "rate limit", prosopite: false do
      it "throttles the 11th wrong attempt within 3 minutes" do
        user
        10.times do
          log_in(password: "wrong")
          expect(flash[:alert]).not_to eq("Try again later.")
        end

        log_in(password: "wrong")

        expect(response).to redirect_to(new_session_url)
        expect(flash[:alert]).to eq("Try again later.")
      end

      it "refuses even the right password once throttled" do
        user
        11.times { log_in(password: "wrong") }

        expect { log_in }.not_to change(Session, :count)

        expect(cookies[:session_id]).to be_blank
      end

      it "allows ten attempts" do
        user
        9.times { log_in(password: "wrong") }

        log_in

        expect(response).to redirect_to(root_url)
        expect(cookies[:session_id]).to be_present
      end
    end
  end

  describe "DELETE /session" do
    before { log_in }

    it "destroys the session record and redirects to the login page" do
      expect { delete session_path }.to change(Session, :count).by(-1)

      expect(response).to redirect_to(new_session_url)
      expect(response).to have_http_status(:see_other)
    end

    it "sends a later GET to the login page" do
      delete session_path

      get root_path

      expect(response).to redirect_to(new_session_url)
    end
  end

  describe "forgery protection" do
    around do |example|
      saved = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = saved
    end

    it "refuses a login POST without an authenticity token" do
      user

      expect { log_in }.not_to change(Session, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(cookies[:session_id]).to be_blank
    end

    it "accepts the login form as rendered, token included" do
      user
      get new_session_path
      token = Nokogiri::HTML(response.body).at_css("form[action='#{session_path}'] input[name='authenticity_token']")["value"]

      post session_path, params: { email_address: user.email_address, password: user.password, authenticity_token: token }

      expect(response).to redirect_to(root_url)
      expect(cookies[:session_id]).to be_present
    end
  end

  describe "a lapsed session" do
    it "sends a request with a tampered session cookie to the login page" do
      log_in
      cookies[:session_id] = "not-a-signed-value"

      get root_path

      expect(response).to redirect_to(new_session_url)
    end

    it "sends a request with a session cookie whose record is gone to the login page" do
      log_in
      Session.delete_all

      get root_path

      expect(response).to redirect_to(new_session_url)
    end
  end
end
