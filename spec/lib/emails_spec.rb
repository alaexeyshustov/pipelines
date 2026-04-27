require 'rails_helper'

RSpec.describe Emails do
  let(:adapter) { instance_double(Emails::Adapters::BaseAdapter) }

  before do
    allow(Emails::Adapters::GmailAdapter).to receive(:from_env).and_return(adapter)
    described_class.configure(gmail: {})
  end

  after do
    described_class.instance_variable_set(:@provider_registry, nil)
  end

  describe '.configure' do
    it 'raises ArgumentError for an unknown provider name' do
      expect { described_class.configure(unknown: {}) }
        .to raise_error(ArgumentError, /Unknown provider 'unknown'/)
    end

    it 'calls from_env on the matching adapter class with the given config' do
      described_class.configure(gmail: { credentials_path: '/tmp/creds.json', token_path: '/tmp/token.yaml' })
      expect(Emails::Adapters::GmailAdapter).to have_received(:from_env)
        .with(credentials_path: '/tmp/creds.json', token_path: '/tmp/token.yaml')
    end

    it 'registers multiple providers at once' do
      yahoo_adapter = instance_double(Emails::Adapters::YahooAdapter)
      allow(Emails::Adapters::YahooAdapter).to receive(:from_env).and_return(yahoo_adapter)

      described_class.configure(gmail: {}, yahoo: {})

      expect(Emails::Adapters::GmailAdapter).to have_received(:from_env).with(no_args).at_least(:once)
      expect(Emails::Adapters::YahooAdapter).to have_received(:from_env).with(no_args).once
    end
  end

  describe '.list_messages' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:list_messages)
        .with(max_results: 10, after_date: nil, before_date: nil, offset: 0, label: nil)
        .and_return([ 'msg1' ])
      expect(described_class.list_messages('gmail', max_results: 10)).to eq([ 'msg1' ])
    end
  end

  describe '.get_message' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:get_message).with('msg_1', label: nil).and_return({ subject: 'Hi' })
      expect(described_class.get_message('gmail', 'msg_1')).to eq({ subject: 'Hi' })
    end
  end

  describe '.search_messages' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:search_messages)
        .with('job offer', max_results: 5, offset: 0, label: nil)
        .and_return([ 'msg2' ])
      expect(described_class.search_messages('gmail', 'job offer', max_results: 5)).to eq([ 'msg2' ])
    end
  end

  describe '.get_labels' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:get_labels).and_return(%w[INBOX JOBS])
      expect(described_class.get_labels('gmail')).to eq(%w[INBOX JOBS])
    end
  end

  describe '.get_unread_count' do
    it 'delegates to the matching adapter' do
      allow(adapter).to receive(:get_unread_count).and_return(42)
      expect(described_class.get_unread_count('gmail')).to eq(42)
    end
  end

  describe '.modify_labels' do
    it 'delegates to the matching adapter with add/remove lists' do
      allow(adapter).to receive(:modify_labels)
        .with('msg_1', add: [ 'JOBS' ], remove: [ 'INBOX' ], source_mailbox: nil)
        .and_return(true)
      expect(described_class.modify_labels('gmail', 'msg_1', add: [ 'JOBS' ], remove: [ 'INBOX' ])).to be(true)
    end

    it 'defaults add and remove to empty arrays' do
      allow(adapter).to receive(:modify_labels).with('msg_1', add: [], remove: [], source_mailbox: nil).and_return(true)
      described_class.modify_labels('gmail', 'msg_1')
      expect(adapter).to have_received(:modify_labels).with('msg_1', add: [], remove: [], source_mailbox: nil)
    end

    it 'forwards the source mailbox when provided' do
      allow(adapter).to receive(:modify_labels)
        .with('msg_1', add: [ '\\Flagged' ], remove: [], source_mailbox: 'Inbox')
        .and_return(true)

      described_class.modify_labels('gmail', 'msg_1', add: [ '\\Flagged' ], source_mailbox: 'Inbox')

      expect(adapter).to have_received(:modify_labels)
        .with('msg_1', add: [ '\\Flagged' ], remove: [], source_mailbox: 'Inbox')
    end
  end

  describe 'unknown provider' do
    it 'raises Emails::ProviderRegistry::UnknownProviderError' do
      expect { described_class.list_messages('outlook') }
        .to raise_error(Emails::ProviderRegistry::UnknownProviderError)
    end
  end

  describe 'auto-loading' do
    it 'auto-loads a known provider from env when not pre-configured' do
      described_class.instance_variable_set(:@provider_registry, nil)
      allow(adapter).to receive(:list_messages).and_return([])
      described_class.list_messages('gmail')
      expect(Emails::Adapters::GmailAdapter).to have_received(:from_env).with(no_args).at_least(:once)
    end
  end
end
