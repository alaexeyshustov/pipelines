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

      expect(Net::IMAP).to have_received(:new).with('imap.mail.yahoo.com', port: 993, ssl: anything, open_timeout: anything)
      expect(imap).to have_received(:login).with('test@yahoo.com', 'secret')
    end

    it 'verifies the server certificate' do
      session.imap

      expect(Net::IMAP).to have_received(:new)
        .with(anything, hash_including(ssl: { verify_mode: OpenSSL::SSL::VERIFY_PEER }))
    end

    it 'sets an explicit connect timeout shorter than the net-imap default of 30 seconds' do
      session.imap

      expect(Net::IMAP).to have_received(:new)
        .with(anything, hash_including(open_timeout: satisfy { |seconds| seconds.positive? && seconds < 30 }))
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
    it 'reads only RFC822.HEADER, not RFC822' do
      header = Net::IMAP::FetchData.new(101, { 'RFC822.HEADER' => 'raw header', 'UID' => 101 })
      allow(imap).to receive(:uid_fetch).and_return([ header ])
      expect(session.fetch_raw_mail(101, Emails::Adapters::YahooAdapter::HEADER_FIELDS)).to eq('raw header')

      whole = Net::IMAP::FetchData.new(101, { 'RFC822' => 'raw mail body', 'UID' => 101 })
      allow(imap).to receive(:uid_fetch).and_return([ whole ])
      expect(session.fetch_raw_mail(101, Emails::Adapters::YahooAdapter::HEADER_FIELDS)).to be_nil
    end

    it 'returns nil when the fetch result is empty' do
      allow(imap).to receive(:uid_fetch).and_return(nil)

      expect(session.fetch_raw_mail(101, %w[RFC822 UID])).to be_nil
    end
  end

  describe '#fetch' do
    it 'returns the FetchData of the message with the requested attributes' do
      fetch_data = Net::IMAP::FetchData.new(101, { 'BODYSTRUCTURE' => nil, 'UID' => 101 })
      allow(imap).to receive(:uid_fetch).and_return([ fetch_data ])

      expect(session.fetch(101, %w[UID BODYSTRUCTURE])).to be(fetch_data)
      expect(imap).to have_received(:uid_fetch).with(101, %w[UID BODYSTRUCTURE])
    end

    it 'returns nil when the UID does not exist' do
      allow(imap).to receive(:uid_fetch).and_return(nil)

      expect(session.fetch(101, %w[UID])).to be_nil
    end

    it 'returns nil for an empty result' do
      allow(imap).to receive(:uid_fetch).and_return([])

      expect(session.fetch(101, %w[UID])).to be_nil
    end

    it 'does not take the lock itself, so callers can hold it' do
      allow(imap).to receive(:uid_fetch).and_return(nil)

      expect { session.with_lock { session.fetch(101, %w[UID]) } }.not_to raise_error
    end
  end

  describe '#uid_validity' do
    it 'reads UIDVALIDITY of the mailbox with STATUS' do
      allow(imap).to receive(:status).with('INBOX', [ 'UIDVALIDITY' ]).and_return({ 'UIDVALIDITY' => 1_700_000_001 })

      expect(session.uid_validity('INBOX')).to eq(1_700_000_001)
    end

    it 'does not take the lock itself, so callers can hold it' do
      allow(imap).to receive(:status).and_return({ 'UIDVALIDITY' => 5 })

      expect { session.with_lock { session.uid_validity('INBOX') } }.not_to raise_error
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
