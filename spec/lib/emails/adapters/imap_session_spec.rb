require 'rails_helper'

RSpec.describe Emails::Adapters::ImapSession do
  subject(:session) do
    described_class.new(
      host:     'imap.mail.yahoo.com',
      port:     993,
      username: 'test@yahoo.com',
      password: 'secret'
    )
  end

  let(:imap) { Net::IMAP.allocate }

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
  end

  describe '#imap' do
    it 'lazily connects and logs in with the configured credentials' do
      session.imap

      expect(Net::IMAP).to have_received(:new).with('imap.mail.yahoo.com', port: 993, ssl: true)
      expect(imap).to have_received(:login).with('test@yahoo.com', 'secret')
    end

    it 'memoizes the connection across calls' do
      2.times { session.imap }

      expect(Net::IMAP).to have_received(:new).once
    end
  end

  describe '#ensure_mailbox' do
    before { allow(imap).to receive(:select) }

    it 'selects the mailbox when switching to a new one' do
      session.ensure_mailbox('INBOX')

      expect(imap).to have_received(:select).with('INBOX')
    end

    it 'does not re-select when already on the requested mailbox' do
      session.ensure_mailbox('INBOX')
      session.ensure_mailbox('INBOX')

      expect(imap).to have_received(:select).once
    end
  end

  describe '#with_lock' do
    it 'yields and returns the block result' do
      result = session.with_lock { 42 }

      expect(result).to eq(42)
    end

    it 'reconnects and retries once when the connection drops' do
      allow(imap).to receive(:select)
      session.ensure_mailbox('INBOX')

      attempts = 0
      result = session.with_lock do
        attempts += 1
        raise IOError, 'connection reset' if attempts == 1

        'recovered'
      end

      expect(result).to eq('recovered')
      expect(attempts).to eq(2)
    end

    it 'raises when the connection drops twice in a row' do
      expect {
        session.with_lock { raise IOError, 'connection reset' }
      }.to raise_error(IOError)
    end
  end

  describe '#fetch_raw_mail' do
    it 'returns the RFC822 body from the fetch result' do
      fetch_data = [ Net::IMAP::FetchData.new(101, { 'RFC822' => 'raw mail body', 'UID' => 101 }) ]
      allow(imap).to receive(:uid_fetch).and_return(fetch_data)

      expect(session.fetch_raw_mail(101, %w[RFC822 UID])).to eq('raw mail body')
    end

    it 'returns nil when the fetch result is empty' do
      allow(imap).to receive(:uid_fetch).and_return(nil)

      expect(session.fetch_raw_mail(101, %w[RFC822 UID])).to be_nil
    end
  end

  describe '#on_exit' do
    it 'logs out and disconnects an open connection' do
      allow(imap).to receive_messages(logout: nil, disconnect: nil)
      session.imap

      session.on_exit

      expect(imap).to have_received(:logout)
      expect(imap).to have_received(:disconnect)
    end

    it 'does nothing when no connection was ever opened' do
      expect { session.on_exit }.not_to raise_error
    end
  end
end
