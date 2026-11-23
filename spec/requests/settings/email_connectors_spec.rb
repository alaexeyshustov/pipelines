require "rails_helper"

RSpec.describe "Settings::EmailConnectors" do
  def session_state
    session[:gmail_oauth].to_h.with_indifferent_access[:state]
  end

  # POST setup must have stored a state, so a callback example never passes only because the session is empty.
  def start_oauth(connector)
    post setup_settings_email_connector_path(connector)
    expect(session_state).to be_present
    session_state
  end

  def capture_log
    io = StringIO.new
    allow(Rails).to receive(:logger).and_return(Logger.new(io))
    io
  end

  def stub_google_token_exchange(status: 200, body: nil)
    body ||= { access_token: "at", refresh_token: "rt", expires_in: 3600, token_type: "Bearer" }
    stub_request(:post, "https://oauth2.googleapis.com/token")
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "GET /settings/email_connectors" do
    it "returns a success response" do
      get settings_email_connectors_path
      expect(response).to be_successful
      expect(response.body).to include("Email Connectors")
    end

    it "asks Turbo to confirm before destroying a connector" do
      connector = EmailConnector.create!(name: "My Gmail", provider: "gmail")

      get settings_email_connectors_path

      destroy = Nokogiri::HTML(response.body).at_css("form[action='#{settings_email_connector_path(connector)}'] button")
      expect(destroy["data-turbo-confirm"]).to eq("Are you sure?")
    end
  end

  describe "GET /settings/email_connectors/:id" do
    it "is not routable" do
      connector = EmailConnector.create!(name: "My Gmail", provider: "gmail")

      get settings_email_connector_path(connector)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /settings/email_connectors/:id/edit" do
    let(:doc) { Nokogiri::HTML(response.body) }

    context "with a yahoo connector" do
      let(:connector) do
        EmailConnector.create!(name: "Y", provider: "yahoo", configuration: { username: "me@yahoo.com", password: "s3cret-pw" })
      end

      before { get edit_settings_email_connector_path(connector) }

      it "shows the stored username" do
        expect(doc.at_css("input[name='email_connector[configuration][username]']")["value"]).to eq("me@yahoo.com")
      end

      it "renders the password input without a value" do
        expect(doc.at_css("input[name='email_connector[configuration][password]']")["value"]).to be_nil
      end

      it "never renders the stored password" do
        expect(response.body).not_to include("s3cret-pw")
      end

      it "has no IMAP host or port inputs" do
        expect(doc.css("input[name*='[host]'], input[name*='[port]']")).to be_empty
      end
    end

    context "with a gmail connector" do
      let(:connector) { EmailConnector.create!(name: "G", provider: "gmail") }

      before { get edit_settings_email_connector_path(connector) }

      it "has no path inputs" do
        expect(doc.css("input[name*='credentials_path'], input[name*='token_path']")).to be_empty
      end

      it "posts to setup from a Connect Gmail button outside the update form" do
        setup_form = doc.at_css("form[action='#{setup_settings_email_connector_path(connector)}']")

        expect(setup_form["method"]).to eq("post")
        expect(setup_form.ancestors("form")).to be_empty
        expect(doc.css("form form")).to be_empty
      end

      it "does not link to setup with a GET" do
        expect(doc.css("a[href='#{setup_settings_email_connector_path(connector)}']")).to be_empty
      end
    end
  end

  describe "POST /settings/email_connectors" do
    it "creates a new EmailConnector" do
      expect {
        post settings_email_connectors_path, params: { email_connector: { name: "My Gmail", provider: "gmail" } }
      }.to change(EmailConnector, :count).by(1)
    end

    it "stores only username and password for yahoo" do
      post settings_email_connectors_path, params: { email_connector: {
        name: "Y", provider: "yahoo",
        configuration: { username: "u", password: "p", host: "evil.example", port: "25", credentials_path: "/etc/passwd", token_path: "/tmp/x" }
      } }

      expect(EmailConnector.last.configuration).to eq("username" => "u", "password" => "p")
    end

    it "stores no configuration for gmail" do
      post settings_email_connectors_path, params: { email_connector: {
        name: "G", provider: "gmail", configuration: { credentials_path: "/etc/passwd", token_path: "/tmp/x" }
      } }

      expect(EmailConnector.last.configuration).to eq({})
    end
  end

  describe "PATCH /settings/email_connectors/:id" do
    let(:connector) do
      EmailConnector.create!(name: "Y", provider: "yahoo", configuration: { username: "me@yahoo.com", password: "s3cret-pw" })
    end

    it "keeps the stored username and password when the password is left blank" do
      patch settings_email_connector_path(connector), params: { email_connector: {
        name: "Renamed", configuration: { username: "me@yahoo.com", password: "" }
      } }

      expect(connector.reload.configuration).to eq("username" => "me@yahoo.com", "password" => "s3cret-pw")
    end

    it "keeps both when no configuration is submitted" do
      patch settings_email_connector_path(connector), params: { email_connector: { name: "Renamed" } }

      expect(connector.reload.configuration).to eq("username" => "me@yahoo.com", "password" => "s3cret-pw")
    end

    it "replaces the password when a new one is submitted and ignores other keys" do
      patch settings_email_connector_path(connector), params: { email_connector: {
        configuration: { password: "rotated", host: "evil.example", port: "25" }
      } }

      expect(connector.reload.configuration).to eq("username" => "me@yahoo.com", "password" => "rotated")
    end

    it "rejects clearing the username and keeps the stored credentials" do
      patch settings_email_connector_path(connector), params: { email_connector: {
        configuration: { username: "", password: "" }
      } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(connector.reload.configuration).to eq("username" => "me@yahoo.com", "password" => "s3cret-pw")
    end
  end

  describe "POST /settings/email_connectors/:id/setup" do
    include_context "with gmail paths from env"

    let(:connector) { EmailConnector.create!(name: "My Gmail", provider: "gmail") }
    let(:google_url) { URI(response.location) }
    let(:google_params) { Rack::Utils.parse_query(google_url.query) }

    it "redirects to the Google authorization URL" do
      post setup_settings_email_connector_path(connector)

      expect(response.location).to start_with("https://accounts.google.com/o/oauth2/auth")
      expect(google_params["redirect_uri"]).to eq(oauth_callback_settings_email_connectors_url)
    end

    it "sends a random state that matches the one kept in the session" do
      post setup_settings_email_connector_path(connector)

      expect(google_params["state"]).to be_present
      expect(google_params["state"]).to eq(session_state)
      expect(session[:gmail_oauth].to_h.with_indifferent_access[:connector_id]).to eq(connector.id)
    end

    it "uses a fresh state per request" do
      post setup_settings_email_connector_path(connector)
      first = session_state
      post setup_settings_email_connector_path(connector)

      expect(session_state).not_to eq(first)
    end

    context "when the credentials file is missing on the server" do
      let(:gmail_credentials_path) { "/nonexistent/secret-dir/credentials.json" }

      it "redirects back to the edit page with a generic alert" do
        post setup_settings_email_connector_path(connector)

        expect(response).to redirect_to(edit_settings_email_connector_path(connector))
        expect(flash[:alert]).to be_present
      end

      it "does not reveal the path" do
        post setup_settings_email_connector_path(connector)
        follow_redirect!

        expect(response.body).not_to include("secret-dir")
        expect(response.body).not_to include("credentials.json")
      end
    end

    context "when the credentials file is malformed" do
      let(:gmail_credentials_path) do
        File.join(gmail_token_dir, "credentials.json").tap { |path| File.write(path, '{ "web": { "client_secret": s3cr3t-value } }') }
      end

      it "redirects back to the edit page with a generic alert and logs the error" do
        log = capture_log

        post setup_settings_email_connector_path(connector)

        expect(response).to redirect_to(edit_settings_email_connector_path(connector))
        expect(flash[:alert]).to eq("Gmail is not configured on the server. Check the server logs.")
        expect(log.string).to match(/Gmail setup failed: Google::Auth::InitializationError/)
      end

      it "does not log the file contents" do
        log = capture_log

        post setup_settings_email_connector_path(connector)

        expect(log.string).not_to include("s3cr3t-value")
      end
    end

    context "when the credentials file cannot be read" do
      let(:gmail_credentials_path) { gmail_token_dir }

      it "redirects back to the edit page with a generic alert and logs the error" do
        log = capture_log

        post setup_settings_email_connector_path(connector)

        expect(response).to redirect_to(edit_settings_email_connector_path(connector))
        expect(flash[:alert]).to eq("Gmail is not configured on the server. Check the server logs.")
        expect(log.string).to include("Gmail setup failed: Errno::")
      end
    end

    context "with a yahoo connector" do
      let(:connector) { EmailConnector.create!(name: "My Yahoo", provider: "yahoo") }

      before do
        allow(Emails::Adapters::GmailSession).to receive(:auth_from_env)
        post setup_settings_email_connector_path(connector)
      end

      it "redirects back to the edit page with an alert" do
        expect(response).to redirect_to(edit_settings_email_connector_path(connector))
        expect(flash[:alert]).to be_present
      end

      it "neither stores an OAuth state nor starts the Google authorization" do
        expect(session[:gmail_oauth]).to be_nil
        expect(Emails::Adapters::GmailSession).not_to have_received(:auth_from_env)
      end
    end

    context "when the connector is not found" do
      it "responds with not found" do
        post setup_settings_email_connector_path(id: 0)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /settings/email_connectors/:id/setup" do
    include_context "with gmail paths from env"

    it "is not routable" do
      connector = EmailConnector.create!(name: "My Gmail", provider: "gmail")

      get setup_settings_email_connector_path(connector)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST setup without a CSRF token" do
    include_context "with gmail paths from env"

    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it "is rejected" do
      connector = EmailConnector.create!(name: "My Gmail", provider: "gmail")

      post setup_settings_email_connector_path(connector)

      expect(response).to have_http_status(:unprocessable_content)
      expect(session[:gmail_oauth]).to be_nil
    end
  end

  describe "GET /settings/email_connectors/oauth_callback" do
    include_context "with gmail paths from env"

    let(:connector) { EmailConnector.create!(name: "My Gmail", provider: "gmail") }
    let(:token_url) { "https://oauth2.googleapis.com/token" }

    let!(:state) { start_oauth(connector) }

    before { stub_google_token_exchange }

    context "with the state from the session" do
      it "exchanges the code and redirects to the edit page" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }

        expect(response).to redirect_to(edit_settings_email_connector_path(connector))
        expect(a_request(:post, token_url).with(body: hash_including("code" => "test_code"))).to have_been_made.once
      end

      it "shows a success notice" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }
        follow_redirect!

        expect(response.body).to include("Gmail connected successfully")
      end

      it "clears the state from the session" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }

        expect(session[:gmail_oauth]).to be_nil
      end

      it "rejects a replay of the same state" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }

        expect(response).to redirect_to(settings_email_connectors_path)
        expect(a_request(:post, token_url)).to have_been_made.once
      end
    end

    context "with a wrong state" do
      before { get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: "forged" } }

      it "is rejected without exchanging the code" do
        expect(response).to be_redirect
        expect(flash[:alert]).to be_present
        expect(a_request(:post, token_url)).not_to have_been_made
      end

      it "does not write a token file" do
        expect(File.exist?(gmail_token_path)).to be(false)
      end
    end

    describe "rejection logging" do
      it "logs a wrong state" do
        log = capture_log

        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: "forged" }

        expect(log.string).to match(/WARN.*Gmail OAuth callback rejected: state mismatch/)
      end

      it "logs a missing state" do
        log = capture_log

        get oauth_callback_settings_email_connectors_path, params: { code: "test_code" }

        expect(log.string).to match(/WARN.*Gmail OAuth callback rejected: callback has no state/)
      end

      it "logs an expired session" do
        reset!
        sign_in_again
        log = capture_log

        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: "anything" }

        expect(log.string).to match(/WARN.*Gmail OAuth callback rejected: no OAuth state in session/)
      end

      it "logs the error Google returned" do
        log = capture_log

        get oauth_callback_settings_email_connectors_path, params: { error: "access_denied", state: }

        expect(log.string).to match(/WARN.*Gmail OAuth callback rejected: Google returned error="access_denied"/)
      end

      it "logs a connector that no longer exists" do
        connector.destroy
        log = capture_log

        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }

        expect(log.string).to match(/WARN.*Gmail OAuth callback rejected: connector #{connector.id} not found/)
      end
    end

    context "with no state" do
      it "is rejected without exchanging the code" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code" }

        expect(response).to be_redirect
        expect(flash[:alert]).to be_present
        expect(a_request(:post, token_url)).not_to have_been_made
      end
    end

    context "when the wrong state was tried first" do
      it "invalidates the session so the right state can no longer be used" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: "forged" }
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }

        expect(a_request(:post, token_url)).not_to have_been_made
      end
    end

    context "when Google reports an error" do
      it "shows a generic alert without exchanging the code" do
        get oauth_callback_settings_email_connectors_path, params: { error: "access_denied", state: }
        follow_redirect!

        expect(flash[:alert]).to be_present
        expect(response.body).not_to include("access_denied")
        expect(a_request(:post, token_url)).not_to have_been_made
      end
    end

    context "when the code exchange fails" do
      before { stub_google_token_exchange(status: 400, body: { error: "invalid_grant", error_description: "Bad code leak" }) }

      it "shows a generic alert without the exception message" do
        get oauth_callback_settings_email_connectors_path, params: { code: "bad", state: }
        follow_redirect!

        expect(flash[:alert]).to be_present
        expect(response.body).not_to include("invalid_grant")
        expect(response.body).not_to include("Bad code leak")
      end

      it "logs the exception" do
        io = StringIO.new
        allow(Rails).to receive(:logger).and_return(Logger.new(io))

        get oauth_callback_settings_email_connectors_path, params: { code: "bad", state: }

        expect(io.string).to include("invalid_grant")
      end
    end

    context "when the connector was deleted meanwhile" do
      it "redirects to the index" do
        connector.destroy

        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: }

        expect(response).to redirect_to(settings_email_connectors_path)
        expect(a_request(:post, token_url)).not_to have_been_made
      end
    end

    context "when the session has expired" do
      it "redirects to the index with an alert" do
        reset!
        sign_in_again
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code", state: "anything" }

        expect(response).to redirect_to(settings_email_connectors_path)
      end
    end
  end

  describe "OAuth callback after the login session lapsed" do
    include_context "with gmail paths from env"

    let(:connector) { EmailConnector.create!(name: "My Gmail", provider: "gmail") }
    let(:callback_params) { { code: "test_code", state: } }
    let!(:state) { start_oauth(connector) }
    let(:token_url) { "https://oauth2.googleapis.com/token" }

    before do
      stub_google_token_exchange
      Session.delete_all
      get oauth_callback_settings_email_connectors_path, params: callback_params
    end

    it "sends the callback to the login page without exchanging the code" do
      expect(response).to redirect_to(new_session_url)
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it "returns to the callback URL after logging in" do
      post session_path, params: { email_address: signed_in_user.email_address, password: signed_in_user.password }

      expect(response).to redirect_to(oauth_callback_settings_email_connectors_url(callback_params))
    end

    it "still completes the exchange with the OAuth state kept through the login" do
      post session_path, params: { email_address: signed_in_user.email_address, password: signed_in_user.password }
      follow_redirect!

      expect(a_request(:post, token_url).with(body: hash_including("code" => "test_code"))).to have_been_made.once
      expect(response).to redirect_to(edit_settings_email_connector_path(connector))
      follow_redirect!
      expect(response.body).to include("Gmail connected successfully")
    end
  end

  describe "POST /settings/email_connectors/:id/test" do
    let(:connector) { EmailConnector.create!(name: "Test Yahoo", provider: "yahoo", configuration: { username: "test@yahoo.com", password: "pwd" }) }
    let(:adapter_spy) { instance_spy(Emails::Adapters::YahooAdapter) }

    before do
      allow(Emails::Adapters::YahooAdapter).to receive(:from_env).and_return(adapter_spy)
      allow(adapter_spy).to receive(:list_messages).with(max_results: 1).and_return([])
    end

    it "calls the adapter to test the connection and records the status" do
      post test_settings_email_connector_path(connector)
      expect(Emails::Adapters::YahooAdapter).to have_received(:from_env).with(username: "test@yahoo.com", password: "pwd")
      expect(adapter_spy).to have_received(:list_messages).with(max_results: 1)
      expect(connector.reload.status).to eq("connected")
    end

    context "when the probe raises" do
      before do
        allow(adapter_spy).to receive(:list_messages).and_raise(StandardError, "boom")
        post test_settings_email_connector_path(connector)
      end

      it "redirects with a generic alert that does not echo the exception message" do
        expect(response).to redirect_to(settings_email_connectors_path)
        expect(flash[:alert]).to be_present.and(satisfy { |message| message.exclude?("boom") })
      end

      it "marks the connector failed" do
        expect(connector.reload.status).to eq("failed")
      end
    end

    context "with a yahoo connector that has no stored credentials" do
      let(:connector) { EmailConnector.create!(name: "Empty Yahoo", provider: "yahoo") }

      around do |example|
        saved = ENV.values_at("YAHOO_USERNAME", "YAHOO_APP_PASSWORD")
        ENV["YAHOO_USERNAME"], ENV["YAHOO_APP_PASSWORD"] = "server@yahoo.com", "server-pwd"
        example.run
      ensure
        ENV["YAHOO_USERNAME"], ENV["YAHOO_APP_PASSWORD"] = saved
      end

      it "fails without falling back to the server's account" do
        post test_settings_email_connector_path(connector)

        expect(Emails::Adapters::YahooAdapter).not_to have_received(:from_env)
        expect(flash[:alert]).to be_present
        expect(connector.reload.status).to eq("failed")
      end

      it "logs why the test failed" do
        log = capture_log

        post test_settings_email_connector_path(connector)

        expect(log.string).to include("Emails::NotConfigured")
      end
    end

    it "redirects with a success message" do
      post test_settings_email_connector_path(connector)
      expect(response).to redirect_to(settings_email_connectors_path)
      follow_redirect!
      expect(response.body).to include("Connection successful!")
    end
  end
end
