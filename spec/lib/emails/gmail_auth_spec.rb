# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::GmailAuth do
  let(:credentials_path) { "credentials.json" }
  let(:token_path) { "token.yaml" }
  let(:callback_uri) { "http://localhost:3000/settings/email_connectors/oauth_callback" }
  let(:output) { StringIO.new }
  let(:auth) { described_class.new(credentials_path:, token_path:, scope: Emails::Adapters::GmailSession::SCOPE, output:) }

  let(:authorizer) { Google::Auth::UserAuthorizer.allocate }

  before do
    client_id   = Google::Auth::ClientId.allocate
    token_store = Google::Auth::Stores::FileTokenStore.allocate
    allow(Google::Auth::ClientId).to receive(:from_file).with(credentials_path).and_return(client_id)
    allow(Google::Auth::Stores::FileTokenStore).to receive(:new).with(file: token_path).and_return(token_store)
    allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
  end

  describe "#authorization_url" do
    it "returns the Google authorization URL for the given callback" do
      url = "https://accounts.google.com/o/oauth2/auth?scope=gmail"
      allow(authorizer).to receive(:get_authorization_url).with(base_url: callback_uri).and_return(url)

      expect(auth.authorization_url(callback_uri:)).to eq(url)
    end
  end

  describe "#credentials" do
    let(:tcp_server) { TCPServer.allocate }
    let(:auth_url) { "https://accounts.google.com/o/oauth2/auth?scope=gmail" }

    before do
      allow(tcp_server).to receive(:addr).and_return([ nil, 3000 ])
      allow(tcp_server).to receive(:close)
      allow(TCPServer).to receive(:new).with("localhost", 0).and_return(tcp_server)
      allow(authorizer).to receive(:get_credentials).with(described_class::USER_ID).and_return(nil)
      allow(authorizer).to receive(:get_authorization_url).with(base_url: "http://localhost:3000").and_return(auth_url)
      allow(auth).to receive(:system)
    end

    it "raises without opening a browser when interactive auth would be required in test" do
      expect { auth.credentials }
        .to raise_error(described_class::InteractiveAuthorizationRequired, /#{Regexp.escape(auth_url)}/)

      expect(auth).not_to have_received(:system)
      expect(tcp_server).to have_received(:close)
    end
  end

  describe "#exchange_code" do
    it "exchanges the code for credentials and returns them" do
      code = "4/abc123"
      credentials = Google::Auth::UserRefreshCredentials.allocate
      allow(authorizer).to receive(:get_and_store_credentials_from_code)
        .with(user_id: described_class::USER_ID, code:, base_url: callback_uri)
        .and_return(credentials)

      expect(auth.exchange_code(code:, callback_uri:)).to eq(credentials)
    end
  end
end
