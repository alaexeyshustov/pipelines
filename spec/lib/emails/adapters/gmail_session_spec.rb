require 'rails_helper'

RSpec.describe Emails::Adapters::GmailSession do
  include GmailHelpers

  before { setup_gmail }
  after  { teardown_gmail }

  describe '.from_env' do
    it 'raises when the credentials file is missing' do
      expect { described_class.from_env(credentials_path: '/nonexistent/path.json', token_path: GmailHelpers.token_path) }
        .to raise_error(/Missing Gmail credentials/)
    end

    it 'returns an initialized, authorized GmailAdapter' do
      adapter = described_class.from_env(
        credentials_path: GmailHelpers::CREDENTIALS_PATH,
        token_path:       GmailHelpers.token_path
      )

      expect(adapter).to be_a(Emails::Adapters::GmailAdapter)
    end
  end

  describe '.reset' do
    let(:token_path) { Rails.root.join('token.yaml').to_s }

    context 'when the token file exists' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(token_path).and_return(true)
        allow(File).to receive(:delete).and_call_original
        allow(File).to receive(:delete).with(token_path)
      end

      it 'deletes the token file' do
        described_class.reset
        expect(File).to have_received(:delete).with(token_path)
      end
    end

    context 'when the token file does not exist' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(token_path).and_return(false)
      end

      it 'does not raise' do
        expect { described_class.reset }.not_to raise_error
      end
    end
  end

  describe '.test_connection' do
    it 'prints a success message when the connection works',
       vcr: { cassette_name: 'emails/adapters/gmail/test_connection',
              record: :none, match_requests_on: %i[method path] } do
      expect {
        described_class.test_connection(
          credentials_path: GmailHelpers::CREDENTIALS_PATH,
          token_path:       GmailHelpers.token_path
        )
      }.to output(/Gmail connection successful/).to_stdout
    end

    it 'prints an error message when the connection fails' do
      allow(described_class).to receive(:from_env).and_raise(StandardError, 'auth failed')

      expect {
        described_class.test_connection
      }.to output(/Gmail connection failed/).to_stdout
    end
  end

  describe '#authorize' do
    it 'delegates to GmailAuth with the session credentials and scope' do
      session     = described_class.new(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)
      auth        = instance_double(Emails::GmailAuth)
      credentials = instance_double(Signet::OAuth2::Client)
      allow(Emails::GmailAuth).to receive(:new).with(
        credentials_path: GmailHelpers::CREDENTIALS_PATH,
        token_path:       GmailHelpers.token_path,
        scope:            described_class::SCOPE
      ).and_return(auth)
      allow(auth).to receive(:credentials).and_return(credentials)

      expect(session.authorize).to eq(credentials)
    end
  end
end
