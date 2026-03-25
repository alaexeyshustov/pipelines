require 'rails_helper'

RSpec.describe Emails::Adapters::GmailAdapter do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env(
      credentials_path: GmailHelpers::CREDENTIALS_PATH,
      token_path:       GmailHelpers::TOKEN_PATH
    )
  end

  before { setup_gmail }
  after  { teardown_gmail }

  describe '#list_messages' do
    it 'returns messages with subject, from, and id',
       vcr: { cassette_name: 'emails/adapters/gmail/list_messages',
              record: :none, match_requests_on: %i[method path] } do
      messages = adapter.list_messages(max_results: 1)

      expect(messages).to be_an(Array)
      expect(messages.first).to include(
        id:      'msg1',
        subject: 'Job Application Update',
        from:    'hr@company.com'
      )
    end

    it 'applies after_date and before_date as query filters',
       vcr: { cassette_name: 'emails/adapters/gmail/list_messages',
              record: :none, match_requests_on: %i[method path] } do
      messages = adapter.list_messages(
        max_results:  1,
        after_date:   Date.new(2026, 1, 1),
        before_date:  Date.new(2026, 3, 31)
      )

      expect(messages).to be_an(Array)
      expect(messages.first).to include(id: 'msg1')
    end

    it 'filters by label_ids when label is given',
       vcr: { cassette_name: 'emails/adapters/gmail/list_messages',
              record: :none, match_requests_on: %i[method path] } do
      messages = adapter.list_messages(max_results: 1, label: 'INBOX')

      expect(messages).to be_an(Array)
      expect(messages.first).to include(id: 'msg1')
    end
  end

  describe '#get_message' do
    it 'returns the full message including a body string',
       vcr: { cassette_name: 'emails/adapters/gmail/get_message',
              record: :none, match_requests_on: %i[method path] } do
      message = adapter.get_message('msg1')

      expect(message).to include(
        id:      'msg1',
        subject: 'Job Application Update',
        from:    'hr@company.com',
        body:    a_kind_of(String)
      )
    end
  end

  describe '#search_messages' do
    it 'returns messages matching the query',
       vcr: { cassette_name: 'emails/adapters/gmail/list_messages',
              record: :none, match_requests_on: %i[method path] } do
      messages = adapter.search_messages('from:hr@company.com', max_results: 1)

      expect(messages).to be_an(Array)
      expect(messages.first).to include(id: 'msg1')
    end
  end

  describe '#get_labels' do
    it 'returns all labels with id, name, and type',
       vcr: { cassette_name: 'emails/adapters/gmail/get_labels',
              record: :none, match_requests_on: %i[method path] } do
      labels = adapter.get_labels

      expect(labels).to be_an(Array)
      expect(labels).to include(
        include(id: 'INBOX',   name: 'INBOX',        type: 'system'),
        include(id: 'Label_1', name: 'applications', type: 'user')
      )
    end
  end

  describe '#get_unread_count' do
    it 'returns the total number of unread messages',
       vcr: { cassette_name: 'emails/adapters/gmail/get_unread_count',
              record: :none, match_requests_on: %i[method path] } do
      count = adapter.get_unread_count

      expect(count).to eq(5)
    end
  end

  describe '#create_label' do
    it 'creates and returns a new label',
       vcr: { cassette_name: 'emails/adapters/gmail/create_label',
              record: :none, match_requests_on: %i[method path] } do
      label = adapter.create_label(name: 'job-applications')

      expect(label).to eq(id: 'Label_2', name: 'job-applications', type: 'user')
    end

    it 'returns the existing label when the name already exists',
       vcr: { cassette_name: 'emails/adapters/gmail/create_label_conflict',
              record: :none, match_requests_on: %i[method path] } do
      label = adapter.create_label(name: 'applications')

      expect(label).to include(id: 'Label_1', name: 'applications')
    end
  end

  describe '#modify_labels' do
    it 'adds labels to a message and returns the updated label list',
       vcr: { cassette_name: 'emails/adapters/gmail/modify_labels_add',
              record: :none, match_requests_on: %i[method path] } do
      result = adapter.modify_labels('msg1', add: [ 'Label_1' ])

      expect(result).to include(id: 'msg1', labels: [ 'INBOX', 'Label_1' ])
    end

    it 'removes labels from a message and returns the updated label list',
       vcr: { cassette_name: 'emails/adapters/gmail/modify_labels_remove',
              record: :none, match_requests_on: %i[method path] } do
      result = adapter.modify_labels('msg1', remove: [ 'INBOX' ])

      expect(result).to include(id: 'msg1', labels: [ 'Label_1' ])
    end

    it 'returns empty labels when a label-conflict error occurs',
       vcr: { cassette_name: 'emails/adapters/gmail/modify_labels_conflict_error',
              record: :none, match_requests_on: %i[method path] } do
      result = adapter.modify_labels('msg1', add: [ 'Label_1' ])

      expect(result).to eq(id: 'msg1', labels: [])
    end

    it 're-raises non-conflict client errors',
       vcr: { cassette_name: 'emails/adapters/gmail/modify_labels_other_error',
              record: :none, match_requests_on: %i[method path] } do
      expect { adapter.modify_labels('msg1', add: [ 'Label_999' ]) }
        .to raise_error(Google::Apis::ClientError)
    end
  end

  describe '#list_messages with offset' do
    it 'skips the first N messages using pagination',
       vcr: { cassette_name: 'emails/adapters/gmail/list_messages_with_offset',
              record: :none, match_requests_on: %i[method path] } do
      messages = adapter.list_messages(max_results: 1, offset: 1)

      expect(messages).to be_an(Array)
      expect(messages.first).to include(id: 'msg1')
    end
  end

  describe '#get_message with multipart body' do
    it 'extracts text/plain from multipart payload',
       vcr: { cassette_name: 'emails/adapters/gmail/get_message_multipart',
              record: :none, match_requests_on: %i[method path] } do
      message = adapter.get_message('msg1')

      expect(message).to include(
        id:   'msg1',
        body: a_kind_of(String)
      )
      expect(message[:body]).not_to be_empty
    end
  end

  describe '.from_env' do
    it 'raises when the credentials file is missing' do
      expect { described_class.from_env(credentials_path: '/nonexistent/path.json', token_path: GmailHelpers::TOKEN_PATH) }
        .to raise_error(/Missing Gmail credentials/)
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
          token_path:       GmailHelpers::TOKEN_PATH
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
end
