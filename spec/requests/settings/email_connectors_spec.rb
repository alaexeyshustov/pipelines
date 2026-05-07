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
