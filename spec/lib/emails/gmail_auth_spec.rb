# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::GmailAuth do
  let(:credentials_path) { "credentials.json" }
  let(:token_path) { "token.yaml" }
  let(:scope) { Emails::Adapters::GmailAdapter::SCOPE }
  let(:callback_uri) { "http://localhost:3000/settings/email_connectors/oauth_callback" }
  let(:auth) { described_class.new(credentials_path:, token_path:, scope:) }

  let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }

  before do
    client_id   = instance_double(Google::Auth::ClientId)
    token_store = instance_double(Google::Auth::Stores::FileTokenStore)
    allow(Google::Auth::ClientId).to receive(:from_file).with(credentials_path).and_return(client_id)
    allow(Google::Auth::Stores::FileTokenStore).to receive(:new).with(file: token_path).and_return(token_store)
    allow(Google::Auth::UserAuthorizer).to receive(:new)
      .with(client_id, scope, token_store, callback_uri:)
      .and_return(authorizer)
  end

  describe "#authorization_url" do
    it "returns the Google authorization URL for the given callback" do
      url = "https://accounts.google.com/o/oauth2/auth?scope=gmail"
      allow(authorizer).to receive(:get_authorization_url).with(base_url: callback_uri).and_return(url)

      expect(auth.authorization_url(callback_uri:)).to eq(url)
    end
  end

  describe "#exchange_code" do
    it "exchanges the code for credentials and returns them" do
      code = "4/abc123"
      credentials = instance_double(Google::Auth::UserRefreshCredentials)
      allow(authorizer).to receive(:get_and_store_credentials_from_code)
        .with(user_id: described_class::USER_ID, code:, base_url: callback_uri)
        .and_return(credentials)

      expect(auth.exchange_code(code:, callback_uri:)).to eq(credentials)
    end
  end
end
