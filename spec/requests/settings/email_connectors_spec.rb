require "rails_helper"

RSpec.describe "Settings::EmailConnectors" do
  describe "GET /settings/email_connectors" do
    it "returns a success response" do
      get settings_email_connectors_path
      expect(response).to be_successful
      expect(response.body).to include("Email Connectors")
    end
  end

  describe "POST /settings/email_connectors" do
    let(:valid_attributes) {
      { name: "My Gmail", provider: "gmail", configuration: { credentials_path: "credentials.json" } }
    }

    it "creates a new EmailConnector" do
      expect {
        post settings_email_connectors_path, params: { email_connector: valid_attributes }
      }.to change(EmailConnector, :count).by(1)
    end
  end

  describe "GET /settings/email_connectors/:id/setup" do
    let(:connector) do
      EmailConnector.create!(
        name: "My Gmail", provider: "gmail",
        configuration: { credentials_path: "credentials.json", token_path: "token.yaml" }
      )
    end
    let(:auth_double) { instance_double(Emails::GmailAuth) }
    let(:auth_url) { "https://accounts.google.com/o/oauth2/auth?scope=gmail" }

    before do
      allow(Emails::GmailAuth).to receive(:new).and_return(auth_double)
      allow(auth_double).to receive(:authorization_url).and_return(auth_url)
    end

    it "redirects to the Google authorization URL" do
      get setup_settings_email_connector_path(connector)
      expect(response).to redirect_to(auth_url)
    end

    it "stores the connector id in the session" do
      get setup_settings_email_connector_path(connector)
      expect(session[:oauth_connector_id]).to eq(connector.id)
    end

    context "when credentials_path does not exist on disk" do
      before do
        allow(auth_double).to receive(:authorization_url)
          .and_raise(Errno::ENOENT, "/missing/credentials.json")
      end

      it "redirects back to the edit page with an alert" do
        get setup_settings_email_connector_path(connector)
        expect(response).to redirect_to(edit_settings_email_connector_path(connector))
      end

      it "shows a helpful error message" do
        get setup_settings_email_connector_path(connector)
        follow_redirect!
        expect(response.body).to include("credentials.json")
      end
    end
  end

  describe "GET /settings/email_connectors/oauth_callback" do
    let(:connector) do
      EmailConnector.create!(
        name: "My Gmail", provider: "gmail",
        configuration: { credentials_path: "credentials.json", token_path: "token.yaml" }
      )
    end
    let(:auth_double) { instance_double(Emails::GmailAuth) }
    let(:auth_url) { "https://accounts.google.com/o/oauth2/auth?scope=gmail" }

    before do
      allow(Emails::GmailAuth).to receive(:new).and_return(auth_double)
      allow(auth_double).to receive(:authorization_url).and_return(auth_url)
      allow(auth_double).to receive(:exchange_code)
    end

    it "exchanges the code and redirects to the edit page" do
      get setup_settings_email_connector_path(connector)
      get oauth_callback_settings_email_connectors_path, params: { code: "test_code" }
      expect(response).to redirect_to(edit_settings_email_connector_path(connector))
    end

    it "shows a success notice" do
      get setup_settings_email_connector_path(connector)
      get oauth_callback_settings_email_connectors_path, params: { code: "test_code" }
      follow_redirect!
      expect(response.body).to include("Gmail connected successfully")
    end

    it "calls exchange_code with the received code" do
      get setup_settings_email_connector_path(connector)
      get oauth_callback_settings_email_connectors_path, params: { code: "test_code" }
      expect(auth_double).to have_received(:exchange_code).with(
        code: "test_code",
        callback_uri: oauth_callback_settings_email_connectors_url
      )
    end

    context "when the session has expired" do
      it "redirects to the index with an alert" do
        get oauth_callback_settings_email_connectors_path, params: { code: "test_code" }
        expect(response).to redirect_to(settings_email_connectors_path)
      end
    end
  end

  describe "POST /settings/email_connectors/:id/test" do
    let(:connector) { EmailConnector.create!(name: "Test Yahoo", provider: "yahoo", configuration: { username: "test@yahoo.com", password: "pwd", host: "localhost", port: 993 }) }
    let(:adapter_spy) { instance_spy(Emails::Adapters::YahooAdapter) }

    before do
      allow(Emails::Adapters::YahooAdapter).to receive(:new).and_return(adapter_spy)
      allow(adapter_spy).to receive(:list_messages).with(max_results: 1).and_return([])
    end

    it "calls the adapter to test the connection" do
      post test_settings_email_connector_path(connector)
      expect(Emails::Adapters::YahooAdapter).to have_received(:new)
      expect(adapter_spy).to have_received(:list_messages).with(max_results: 1)
    end

    it "redirects with a success message" do
      post test_settings_email_connector_path(connector)
      expect(response).to redirect_to(settings_email_connectors_path)
      follow_redirect!
      expect(response.body).to include("Connection successful!")
    end
  end
end
