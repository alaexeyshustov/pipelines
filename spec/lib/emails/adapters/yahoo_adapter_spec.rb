require 'rails_helper'

RSpec.describe Emails::Adapters::YahooAdapter do
  subject(:adapter) do
    described_class.new(
      host:     'imap.mail.yahoo.com',
      port:     993,
      username: 'test@yahoo.com',
      password: 'secret'
    )
  end

  let(:imap) { instance_double(Net::IMAP) }

  let(:header_text) do
    "Subject: Job Application Update\r\n" \
    "From: hr@company.com\r\n" \
    "To: test@yahoo.com\r\n" \
    "Date: Mon, 1 Jan 2026 12:00:00 +0000\r\n\r\n"
  end

  let(:fetch_data) do
    [ instance_double(Net::IMAP::FetchData, attr: { 'RFC822.HEADER' => header_text, 'FLAGS' => [], 'UID' => 101 }) ]
  end

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
  end


  describe '#list_messages' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive_messages(uid_search: [ 101 ], uid_fetch: fetch_data)
    end

    it 'returns messages with subject, from, and id' do
      messages = adapter.list_messages(max_results: 10)

      expect(messages).to be_an(Array)
      expect(messages.first).to include(
        id:      101,
        subject: 'Job Application Update',
        from:    'hr@company.com'
      )
    end

    it 'limits the number of results by max_results' do
      allow(imap).to receive(:uid_search).and_return([ 101, 102, 103 ])

      messages = adapter.list_messages(max_results: 1)

      expect(messages.length).to eq(1)
    end

    it 'applies SINCE and BEFORE date filters in the search criteria' do
      adapter.list_messages(
        max_results:  10,
        after_date:   Date.new(2026, 1, 1),
        before_date:  Date.new(2026, 3, 31)
      )

      expect(imap).to have_received(:uid_search).with(
        include('SINCE', '01-Jan-2026', 'BEFORE', '31-Mar-2026')
      )
    end

    it 'adds query terms to search criteria' do
      adapter.search_messages('from:hr@company.com', max_results: 10)

      expect(imap).to have_received(:uid_search).with(include('FROM', 'hr@company.com'))
    end
  end

  describe '#get_message' do
    let(:full_message_text) do
      header_text + "We are pleased to inform you that your application was successful.\r\n"
    end

    let(:full_fetch_data) do
      [ instance_double(Net::IMAP::FetchData, attr: { 'RFC822' => full_message_text, 'FLAGS' => [], 'UID' => 101 }) ]
    end

    before do
      allow(imap).to receive(:select)
      allow(imap).to receive(:uid_fetch).with(101, anything).and_return(full_fetch_data)
    end

    it 'returns the message for the given uid' do
      message = adapter.get_message(101)

      expect(message).to include(
        id:      101,
        subject: 'Job Application Update',
        from:    'hr@company.com'
      )
    end

    it 'includes the message body' do
      message = adapter.get_message(101)

      expect(message[:body]).to include('application was successful')
    end

    it 'fetches the full RFC822 message' do
      adapter.get_message(101)

      expect(imap).to have_received(:uid_fetch).with(101, include('RFC822'))
    end
  end

  describe '#get_labels' do
    let(:mailbox) { instance_double(Net::IMAP::MailboxList, name: 'INBOX', delim: '/', attr: [ :Noselect ]) }

    before do
      allow(imap).to receive(:list).with('', '*').and_return([ mailbox ])
    end

    it 'returns folders as labels with id, name, and type' do
      labels = adapter.get_labels

      expect(labels).to be_an(Array)
      expect(labels.first).to include(id: 'INBOX', name: 'INBOX')
    end
  end

  describe '#get_unread_count' do
    before do
      allow(imap).to receive(:status).with('INBOX', [ 'UNSEEN' ]).and_return({ 'UNSEEN' => 7 })
    end

    it 'returns the number of unseen messages in the inbox' do
      count = adapter.get_unread_count

      expect(count).to eq(7)
    end
  end

  describe '#create_label' do
    before { allow(imap).to receive(:create) }

    it 'creates an IMAP folder and returns it as a label' do
      label = adapter.create_label(name: 'job-applications')

      expect(imap).to have_received(:create).with('job-applications')
      expect(label).to eq(id: 'job-applications', name: 'job-applications', type: 'user')
    end
  end

  describe '#modify_labels' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive(:uid_copy)
      allow(imap).to receive(:uid_store)
      allow(imap).to receive(:expunge)
    end

    it 'copies message to the label folder when adding a label' do
      adapter.modify_labels(101, add: [ 'job-applications' ])

      expect(imap).to have_received(:uid_copy).with(101, 'job-applications')
    end

    it 'adds IMAP flags in the source mailbox when adding Yahoo flags' do
      adapter.modify_labels(101, add: [ '\\Flagged' ], source_mailbox: 'Inbox')

      expect(imap).to have_received(:select).with('Inbox')
      expect(imap).to have_received(:uid_store).with(101, '+FLAGS', [ '\\Flagged' ])
      expect(imap).not_to have_received(:uid_copy).with(101, '\\Flagged')
    end

    it 'copies from INBOX by default when adding a label' do
      adapter.modify_labels(101, add: [ 'job-applications' ])

      expect(imap).to have_received(:select).with('INBOX')
    end

    it 'copies from the specified source_mailbox' do
      adapter.modify_labels(101, add: [ 'job-applications' ], source_mailbox: 'Sent')

      expect(imap).to have_received(:select).with('Sent')
    end

    it 'copies to multiple folders in a single operation' do
      adapter.modify_labels(101, add: [ 'job-applications', 'interviews' ])

      expect(imap).to have_received(:uid_copy).with(101, 'job-applications')
      expect(imap).to have_received(:uid_copy).with(101, 'interviews')
    end

    it 'selects the label folder and marks deleted when removing a label' do
      adapter.modify_labels(101, remove: [ 'job-applications' ])

      expect(imap).to have_received(:select).with('job-applications')
      expect(imap).to have_received(:uid_store).with(101, '+FLAGS', [ :Deleted ])
      expect(imap).to have_received(:expunge)
    end

    it 'removes IMAP flags from the source mailbox when removing Yahoo flags' do
      adapter.modify_labels(101, remove: [ '\\Flagged' ], source_mailbox: 'Inbox')

      expect(imap).to have_received(:select).with('Inbox')
      expect(imap).to have_received(:uid_store).with(101, '-FLAGS', [ '\\Flagged' ])
      expect(imap).not_to have_received(:expunge)
    end

    it 'selects each folder when removing from multiple folders' do
      adapter.modify_labels(101, remove: [ 'job-applications', 'interviews' ])

      expect(imap).to have_received(:select).with('job-applications')
      expect(imap).to have_received(:select).with('interviews')
    end

    it 'marks messages deleted and expunges in each folder' do
      adapter.modify_labels(101, remove: [ 'job-applications', 'interviews' ])

      expect(imap).to have_received(:uid_store).with(101, '+FLAGS', [ :Deleted ]).twice
      expect(imap).to have_received(:expunge).twice
    end

    it 'returns uid, added, and removed' do
      result = adapter.modify_labels(101, add: [ 'job-applications' ], remove: [ 'archive' ])

      expect(result).to eq(message_id: 101, added: [ 'job-applications' ], removed: [ 'archive' ])
    end
  end

  describe '#search_messages' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive_messages(uid_search: [ 101 ], uid_fetch: fetch_data)
    end

    it 'searches using the given query' do
      messages = adapter.search_messages('from:hr@company.com', max_results: 5)

      expect(messages).to be_an(Array)
      expect(imap).to have_received(:uid_search).with(include('FROM', 'hr@company.com'))
    end
  end

  describe '#on_exit' do
    before do
      allow(imap).to receive(:status).and_return({ "UNSEEN" => 0 })
      adapter.get_unread_count # trigger lazy connection
      allow(imap).to receive(:logout)
      allow(imap).to receive(:disconnect)
    end

    it 'disconnects the IMAP connection' do
      adapter.on_exit

      expect(imap).to have_received(:logout)
      expect(imap).to have_received(:disconnect)
    end
  end

  describe 'reconnection on broken connection' do
    before do
      allow(imap).to receive(:select)
      call_count = 0
      allow(imap).to receive(:uid_search) do
        call_count += 1
        raise IOError, 'connection reset' if call_count == 1
        [ 101 ]
      end
      allow(imap).to receive(:uid_fetch).and_return(fetch_data)
    end

    it 'reconnects and retries when the IMAP connection drops' do
      messages = adapter.list_messages(max_results: 10)

      expect(messages).to be_an(Array)
    end
  end

  describe 'fetch_and_parse error handling' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive_messages(uid_search: [ 101 ], uid_fetch: [ instance_double(Net::IMAP::FetchData, attr: { 'RFC822.HEADER' => '', 'RFC822' => nil, 'FLAGS' => [], 'UID' => 101 }) ])
    end

    it 'skips messages that fail to parse' do
      messages = adapter.list_messages(max_results: 10)

      expect(messages).to be_an(Array)
    end
  end

  describe '.from_env' do
    it 'creates an adapter from explicit credentials' do
      allow(imap).to receive(:select)

      adapter = described_class.from_env(
        username: 'user@yahoo.com',
        password: 'secret',
        host:     'imap.mail.yahoo.com',
        port:     993
      )

      expect(adapter).to be_a(described_class)
    end

    it 'raises when credentials are missing' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('YAHOO_USERNAME').and_return(nil)
      allow(ENV).to receive(:[]).with('YAHOO_APP_PASSWORD').and_return(nil)

      expect { described_class.from_env(username: nil, password: nil) }
        .to raise_error(/Missing Yahoo credentials/)
    end
  end

  describe '.reset' do
    it 'does not raise' do
      expect { described_class.reset }.not_to raise_error
    end
  end

  describe '.test_connection' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive(:uid_search).and_return([])
    end

    it 'prints a success message when the connection works' do
      expect {
        described_class.test_connection(
          username: 'test@yahoo.com',
          password: 'secret',
          host:     'imap.mail.yahoo.com',
          port:     993
        )
      }.to output(/Yahoo Mail connection successful/).to_stdout
    end

    it 'prints an error message when the connection fails' do
      allow(imap).to receive(:login).and_raise(StandardError, 'auth failed')

      expect {
        described_class.test_connection(username: 'test@yahoo.com', password: 'secret')
      }.to output(/Yahoo Mail connection failed/).to_stdout
    end
  end

  describe 'query criteria parsing' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive(:uid_fetch).and_return([])
    end

    it 'translates to: prefix to IMAP TO criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('to:recruiter@company.com', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('TO', 'recruiter@company.com'))
    end

    it 'translates subject: prefix to IMAP SUBJECT criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('subject:interview', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('SUBJECT', 'interview'))
    end

    it 'translates is:unread to IMAP UNSEEN criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('is:unread', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('UNSEEN'))
    end

    it 'translates is:read to IMAP SEEN criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('is:read', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('SEEN'))
    end

    it 'translates is:flagged to IMAP FLAGGED criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('is:flagged', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('FLAGGED'))
    end

    it 'translates after: date to IMAP SINCE criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('after:2026-01-01', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('SINCE', '01-Jan-2026'))
    end

    it 'translates before: date to IMAP BEFORE criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('before:2026-03-31', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('BEFORE', '31-Mar-2026'))
    end

    it 'translates bare words to IMAP TEXT criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.search_messages('software engineer', max_results: 10)
      expect(imap).to have_received(:uid_search).with(include('TEXT', 'software engineer'))
    end
  end
end
