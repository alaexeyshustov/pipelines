require 'rails_helper'

RSpec.describe Emails::Adapters::GmailSession do
  include GmailHelpers
  include_context 'with gmail paths from env'

  let(:gmail_token_path) { GmailHelpers.token_path }

  before { write_gmail_token(gmail_token_path) }
  after  { FileUtils.rm_f(GmailHelpers.token_path) }

  describe '.from_env' do
    context 'when the credentials file is missing' do
      let(:gmail_credentials_path) { '/nonexistent/path.json' }

      it 'raises' do
        expect { described_class.from_env }.to raise_error(Emails::NotConfigured, /Missing Gmail credentials/)
      end
    end

    it 'returns an initialized, authorized GmailAdapter' do
      expect(described_class.from_env).to be_a(Emails::Adapters::GmailAdapter)
    end
  end

  describe '.auth_from_env' do
    it 'returns a GmailAuth over the GMAIL_TOKEN_PATH token' do
      auth = described_class.auth_from_env

      expect(auth).to be_a(Emails::GmailAuth)
      expect(auth.credentials.refresh_token).to eq('test_refresh_token')
    end

    context 'when the credentials file is missing' do
      let(:gmail_credentials_path) { '/nonexistent/secret-dir/credentials.json' }

      it 'raises NotConfigured' do
        expect { described_class.auth_from_env }.to raise_error(Emails::NotConfigured)
      end
    end
  end

  describe '.reset' do
    let(:gmail_token_path) { File.join(gmail_token_dir, 'configured_token.yaml') }
    let(:token_path) { gmail_token_path }

    context 'when the token file exists' do
      it 'deletes the configured token file' do
        described_class.reset

        expect(File.exist?(token_path)).to be(false)
      end

      it 'leaves the default token.yaml alone' do
        default = Rails.root.join('token.yaml').to_s
        allow(File).to receive(:delete).and_call_original

        described_class.reset

        expect(File).not_to have_received(:delete).with(default)
      end
    end

    context 'when the token file does not exist' do
      before { FileUtils.rm_f(token_path) }

      it 'does not raise' do
        expect { described_class.reset }.not_to raise_error
      end
    end
  end

  describe '.test_connection' do
    it 'returns a success message when the connection works',
       vcr: { cassette_name: 'emails/adapters/gmail/test_connection',
              record: :none, match_requests_on: %i[method path] } do
      status = described_class.test_connection

      expect(status).to match(/Gmail connection successful/)
    end

    it 'probes the profile once with the already authorized adapter' do
      profile = stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/profile")
                .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                           body: { emailAddress: 'me@gmail.com', historyId: '1' }.to_json)

      expect(described_class.test_connection).to match(/Gmail connection successful/)
      expect(profile).to have_been_requested.once
    end

    it 'returns an error message when the connection fails' do
      allow(described_class).to receive(:from_env).and_raise(StandardError, 'auth failed')

      expect(described_class.test_connection).to match(/Gmail connection failed/)
    end
  end

  describe '.setup' do
    it 'runs the interactive authorization with the configured paths' do
      auth = Emails::GmailAuth.allocate
      allow(auth).to receive(:credentials)
      allow(Emails::GmailAuth).to receive(:new).and_return(auth)

      described_class.setup

      expect(auth).to have_received(:credentials).with(interactive: true)
    end
  end

  describe '#authorize' do
    it 'raises NotConfigured instead of starting interactive authorization when no token is stored' do
      session = described_class.new(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: '/tmp/no_such_token.yaml')

      expect { session.authorize }.to raise_error(Emails::NotConfigured, /no_such_token\.yaml/)
    end

    it 'returns credentials loaded from the stored token' do
      session = described_class.new(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)

      credentials = session.authorize

      expect(credentials).to be_a(Signet::OAuth2::Client)
      expect(credentials.refresh_token).to eq('test_refresh_token')
    end
  end
end
