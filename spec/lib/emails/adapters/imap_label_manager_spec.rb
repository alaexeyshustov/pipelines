require 'rails_helper'

RSpec.describe Emails::Adapters::ImapLabelManager do
  subject(:manager) { described_class.new(session: session) }

  let(:session) do
    Emails::Adapters::ImapSession.new(
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
    allow(imap).to receive(:select)
  end

  def imap_no_response_error(text)
    response = Struct.new(:data).new(Net::IMAP::ResponseText.new(nil, text))
    Net::IMAP::NoResponseError.new(response)
  end

  describe '#create_label' do
    it 'creates an IMAP folder and returns it as a label' do
      allow(imap).to receive(:create)

      label = manager.create_label(name: 'applications')

      expect(imap).to have_received(:create).with('applications')
      expect(label).to eq(id: 'applications', name: 'applications', type: 'user')
    end

    it 'returns the existing folder as a label when it already exists' do
      allow(imap).to receive(:create).and_raise(imap_no_response_error('CREATE failed - Mailbox exists'))

      expect(manager.create_label(name: 'applications')).to eq(id: 'applications', name: 'applications', type: 'user')
    end

    it 're-raises other IMAP errors' do
      allow(imap).to receive(:create).and_raise(imap_no_response_error('unrelated failure'))

      expect { manager.create_label(name: 'applications') }.to raise_error(Net::IMAP::NoResponseError)
    end
  end

  describe '#add_labels' do
    it 'copies the message into the label folder for a non-flag label' do
      allow(imap).to receive(:uid_copy)

      manager.add_labels(101, [ 'applications' ], 'INBOX')

      expect(imap).to have_received(:select).with('INBOX')
      expect(imap).to have_received(:uid_copy).with(101, 'applications')
    end

    it 'stores the flag in the source mailbox for a Yahoo flag label' do
      allow(imap).to receive(:uid_store)

      manager.add_labels(101, [ '\\Flagged' ], 'INBOX')

      expect(imap).to have_received(:select).with('INBOX')
      expect(imap).to have_received(:uid_store).with(101, '+FLAGS', [ '\\Flagged' ])
    end
  end

  describe '#remove_labels' do
    it 'selects the label folder, marks deleted, and expunges for a non-flag label' do
      allow(imap).to receive_messages(uid_store: nil, expunge: nil)

      manager.remove_labels(101, [ 'applications' ], 'INBOX')

      expect(imap).to have_received(:select).with('applications')
      expect(imap).to have_received(:uid_store).with(101, '+FLAGS', [ :Deleted ])
      expect(imap).to have_received(:expunge)
    end

    it 'removes the flag from the source mailbox for a Yahoo flag label' do
      allow(imap).to receive(:uid_store)

      manager.remove_labels(101, [ '\\Flagged' ], 'INBOX')

      expect(imap).to have_received(:select).with('INBOX')
      expect(imap).to have_received(:uid_store).with(101, '-FLAGS', [ '\\Flagged' ])
    end

    it 'processes multiple labels independently' do
      allow(imap).to receive_messages(uid_store: nil, expunge: nil, uid_copy: nil)

      manager.remove_labels(101, [ 'applications', 'archive' ], 'INBOX')

      expect(imap).to have_received(:select).with('applications')
      expect(imap).to have_received(:select).with('archive')
    end
  end
end
