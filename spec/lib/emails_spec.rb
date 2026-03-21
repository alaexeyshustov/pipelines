require 'rails_helper'

RSpec.describe Emails do
  let(:adapter) { instance_double(Emails::Adapters::BaseAdapter) }

  before do
    allow(Emails::Adapters::GmailAdapter).to receive(:from_env).and_return(adapter)
    Emails.configure(gmail: {})
  end

  after do
    Emails.instance_variable_set(:@provider_registry, nil)
  end

  describe '.configure' do
    it 'raises ArgumentError for an unknown provider name' do
      expect { Emails.configure(unknown: {}) }
        .to raise_error(ArgumentError, /Unknown provider 'unknown'/)
    end

    it 'calls from_env on the matching adapter class with the given config' do
      Emails.configure(gmail: { credentials_path: '/tmp/creds.json', token_path: '/tmp/token.yaml' })
      expect(Emails::Adapters::GmailAdapter).to have_received(:from_env)
        .with(credentials_path: '/tmp/creds.json', token_path: '/tmp/token.yaml')
    end

    it 'registers multiple providers at once' do
      yahoo_adapter = instance_double(Emails::Adapters::YahooAdapter)
      allow(Emails::Adapters::YahooAdapter).to receive(:from_env).and_return(yahoo_adapter)

      Emails.configure(gmail: {}, yahoo: {})

      expect(Emails::Adapters::GmailAdapter).to have_received(:from_env).with(no_args).at_least(:once)
      expect(Emails::Adapters::YahooAdapter).to have_received(:from_env).with(no_args).once
    end
  end

  describe '.list_messages' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:list_messages).with(max: 10).and_return([ 'msg1' ])
      expect(Emails.list_messages('gmail', max: 10)).to eq([ 'msg1' ])
    end
  end

  describe '.get_message' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:get_message).with('msg_1', format: :full).and_return({ subject: 'Hi' })
      expect(Emails.get_message('gmail', 'msg_1', format: :full)).to eq({ subject: 'Hi' })
    end
  end

  describe '.search_messages' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:search_messages).with('job offer', max: 5).and_return([ 'msg2' ])
      expect(Emails.search_messages('gmail', 'job offer', max: 5)).to eq([ 'msg2' ])
    end
  end

  describe '.get_labels' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:get_labels).and_return(%w[INBOX JOBS])
      expect(Emails.get_labels('gmail')).to eq(%w[INBOX JOBS])
    end
  end

  describe '.get_unread_count' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:get_unread_count).and_return(42)
      expect(Emails.get_unread_count('gmail')).to eq(42)
    end
  end

  describe '.modify_labels' do
    it 'delegates to the matching adapter with add/remove lists' do
      allow(adapter).to receive(:modify_labels).with('msg_1', add: [ 'JOBS' ], remove: [ 'INBOX' ]).and_return(true)
      expect(Emails.modify_labels('gmail', 'msg_1', add: [ 'JOBS' ], remove: [ 'INBOX' ])).to be(true)
    end

    it 'defaults add and remove to empty arrays' do
      allow(adapter).to receive(:modify_labels).with('msg_1', add: [], remove: []).and_return(true)
      Emails.modify_labels('gmail', 'msg_1')
    end
  end

  describe 'unknown provider' do
    it 'raises Emails::ProviderRegistry::UnknownProviderError' do
      expect { Emails.list_messages('outlook') }
        .to raise_error(Emails::ProviderRegistry::UnknownProviderError)
    end
  end

  describe 'auto-loading' do
    it 'auto-loads a known provider from env when not pre-configured' do
      Emails.instance_variable_set(:@provider_registry, nil)
      allow(adapter).to receive(:list_messages).and_return([])
      Emails.list_messages('gmail')
      expect(Emails::Adapters::GmailAdapter).to have_received(:from_env).with(no_args).at_least(:once)
    end
  end
end
