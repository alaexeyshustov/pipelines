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
    [ double('FetchData', attr: { 'RFC822.HEADER' => header_text, 'FLAGS' => [], 'UID' => 101 }) ]
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
      adapter.list_messages(max_results: 10, query: 'from:hr@company.com')

      expect(imap).to have_received(:uid_search).with(include('FROM', 'hr@company.com'))
    end
  end

  describe '#get_message' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive(:uid_fetch).with(101, anything).and_return(fetch_data)
    end

    it 'returns the message for the given uid' do
      message = adapter.get_message(101)

      expect(message).to include(
        id:      101,
        subject: 'Job Application Update',
        from:    'hr@company.com'
      )
    end
  end

  describe '#get_labels' do
    let(:mailbox) { double('Mailbox', name: 'INBOX', delim: '/', attr: [ :Noselect ]) }

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
      allow(imap).to receive(:uid_store)
    end

    it 'adds labels by storing IMAP flags' do
      adapter.modify_labels(101, add: [ '\\Flagged' ], mailbox: 'INBOX')

      expect(imap).to have_received(:uid_store).with(101, '+FLAGS', anything)
    end

    it 'removes labels by clearing IMAP flags' do
      adapter.modify_labels(101, remove: [ '\\Flagged' ], mailbox: 'INBOX')

      expect(imap).to have_received(:uid_store).with(101, '-FLAGS', anything)
    end

    context 'when uid_store raises BadResponseError for invalid arguments' do
      let(:bad_response) do
        resp = double('BadResponse')
        data = double('ResponseData', text: 'UID STORE Command arguments invalid foo')
        allow(resp).to receive_messages(data: data, to_s: 'UID STORE Command arguments invalid foo')
        resp
      end

      before do
        allow(Pry).to receive(:start)
        allow(imap).to receive(:uid_store).and_raise(Net::IMAP::BadResponseError.new(bad_response))
      end

      it 'returns a result hash instead of re-raising' do
        result = adapter.modify_labels(101, add: [ '\\InvalidFlag' ], mailbox: 'INBOX')

        expect(result).to include(uid: 101, action: 'add')
      end
    end
  end

  describe '#search_messages' do
    before do
      allow(imap).to receive(:select)
      allow(imap).to receive_messages(uid_search: [ 101 ], uid_fetch: fetch_data)
    end

    it 'delegates to list_messages with the given query' do
      messages = adapter.search_messages('from:hr@company.com', max_results: 5, mailbox: 'INBOX')

      expect(messages).to be_an(Array)
      expect(imap).to have_received(:uid_search).with(include('FROM', 'hr@company.com'))
    end
  end

  describe '#at_exit' do
    before do
      allow(imap).to receive(:logout)
      allow(imap).to receive(:disconnect)
    end

    it 'disconnects the IMAP connection' do
      adapter.at_exit

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
      allow(imap).to receive_messages(uid_search: [ 101 ], uid_fetch: [ double('FetchData', attr: { 'RFC822.HEADER' => '', 'FLAGS' => [], 'UID' => 101 }) ])
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
      adapter.list_messages(max_results: 10, query: 'to:recruiter@company.com')
      expect(imap).to have_received(:uid_search).with(include('TO', 'recruiter@company.com'))
    end

    it 'translates subject: prefix to IMAP SUBJECT criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'subject:interview')
      expect(imap).to have_received(:uid_search).with(include('SUBJECT', 'interview'))
    end

    it 'translates is:unread to IMAP UNSEEN criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'is:unread')
      expect(imap).to have_received(:uid_search).with(include('UNSEEN'))
    end

    it 'translates is:read to IMAP SEEN criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'is:read')
      expect(imap).to have_received(:uid_search).with(include('SEEN'))
    end

    it 'translates is:flagged to IMAP FLAGGED criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'is:flagged')
      expect(imap).to have_received(:uid_search).with(include('FLAGGED'))
    end

    it 'translates after: date to IMAP SINCE criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'after:2026-01-01')
      expect(imap).to have_received(:uid_search).with(include('SINCE', '01-Jan-2026'))
    end

    it 'translates before: date to IMAP BEFORE criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'before:2026-03-31')
      expect(imap).to have_received(:uid_search).with(include('BEFORE', '31-Mar-2026'))
    end

    it 'translates bare words to IMAP TEXT criterion' do
      allow(imap).to receive(:uid_search).and_return([])
      adapter.list_messages(max_results: 10, query: 'software engineer')
      expect(imap).to have_received(:uid_search).with(include('TEXT', 'software engineer'))
    end
  end
end
