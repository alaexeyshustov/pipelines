require 'rails_helper'

RSpec.describe Emails::MessageScope do
  subject(:scope) { described_class.new }

  def gmail_message(id) = { id: id, provider: 'gmail', labels: [ 'INBOX' ] }
  def yahoo_message(id, labels) = { id: id, provider: 'yahoo', labels: labels }

  describe '#allow?' do
    it 'refuses Gmail and Yahoo ids on a new scope' do
      expect(scope.allow?(provider: 'gmail', message_id: 'm1')).to be false
      expect(scope.allow?(provider: 'yahoo', message_id: '42')).to be false
    end

    context 'with a recorded Gmail message' do
      before { scope.record([ gmail_message('m1') ]) }

      it 'allows the recorded id with or without a mailbox' do
        expect(scope.allow?(provider: 'gmail', message_id: 'm1')).to be true
        expect(scope.allow?(provider: 'gmail', message_id: 'm1', mailbox: 'Sent')).to be true
      end

      it 'refuses another id' do
        expect(scope.allow?(provider: 'gmail', message_id: 'm2')).to be false
      end

      it 'refuses the same id under another provider' do
        expect(scope.allow?(provider: 'yahoo', message_id: 'm1')).to be false
      end
    end

    context 'with a Yahoo message recorded in Sent' do
      before { scope.record([ yahoo_message('42', [ 'Sent' ]) ]) }

      it 'allows the recorded mailbox, case-insensitively' do
        expect(scope.allow?(provider: 'yahoo', message_id: '42', mailbox: 'Sent')).to be true
        expect(scope.allow?(provider: 'yahoo', message_id: '42', mailbox: 'sent')).to be true
      end

      [ nil, 'INBOX', 'Archive' ].each do |mailbox|
        it "refuses the same uid in mailbox #{mailbox.inspect}" do
          expect(scope.allow?(provider: 'yahoo', message_id: '42', mailbox: mailbox)).to be false
        end
      end
    end

    [ [ 'INBOX' ], [] ].each do |labels|
      context "with a Yahoo message recorded with labels #{labels.inspect}" do
        before { scope.record([ yahoo_message('42', labels) ]) }

        inbox_aliases = [ nil, '', 'Inbox' ]

        inbox_aliases.each do |mailbox|
          it "treats mailbox #{mailbox.inspect} as INBOX" do
            expect(scope.allow?(provider: 'yahoo', message_id: '42', mailbox: mailbox)).to be true
          end
        end

        it 'treats an omitted mailbox as INBOX' do
          expect(scope.allow?(provider: 'yahoo', message_id: '42')).to be true
        end
      end
    end

    it 'compares ids as exact strings' do
      scope.record([ yahoo_message('42', [ 'INBOX' ]) ])

      [ '123:42', '42abc', ' 42', '4' ].each do |id|
        expect(scope.allow?(provider: 'yahoo', message_id: id)).to be(false), "expected #{id.inspect} to be refused"
      end
    end

    it 'does not share keys between scope instances' do
      scope.record([ gmail_message('m1') ])

      expect(described_class.new.allow?(provider: 'gmail', message_id: 'm1')).to be false
    end
  end

  describe '#record' do
    it 'returns its argument unchanged' do
      messages = [ gmail_message('m1') ]

      expect(scope.record(messages)).to be(messages)
    end

    it 'ignores values that are not an array' do
      expect { scope.record(nil) }.not_to raise_error
      expect { scope.record({ error: 'x' }) }.not_to raise_error
      expect(scope.allow?(provider: 'gmail', message_id: 'x')).to be false
    end

    it 'skips non-hash items and items without an id' do
      expect { scope.record([ 'm1', nil, { id: nil, provider: 'gmail', labels: [] } ]) }.not_to raise_error
      expect(scope.allow?(provider: 'gmail', message_id: 'm1')).to be false
      expect(scope.allow?(provider: 'gmail', message_id: '')).to be false
    end

    it 'still records the valid items next to skipped ones' do
      scope.record([ nil, gmail_message('m1') ])

      expect(scope.allow?(provider: 'gmail', message_id: 'm1')).to be true
    end
  end

  describe 'edge cases' do
    it 'records an Integer id as a string, so only the string form is allowed (fail closed)' do
      scope.record([ { id: 42, provider: 'gmail', labels: [] } ])

      expect(scope.allow?(provider: 'gmail', message_id: '42')).to be true
      expect(scope.allow?(provider: 'gmail', message_id: 42)).to be false
    end

    it 'does not allow a message recorded without a provider under gmail or yahoo' do
      scope.record([ { id: 'm1', labels: [ 'INBOX' ] } ])

      expect(scope.allow?(provider: 'gmail', message_id: 'm1')).to be false
      expect(scope.allow?(provider: 'yahoo', message_id: 'm1')).to be false
    end

    it 'treats a Yahoo message with nil labels as INBOX' do
      scope.record([ yahoo_message('7', nil) ])

      expect(scope.allow?(provider: 'yahoo', message_id: '7', mailbox: 'INBOX')).to be true
      expect(scope.allow?(provider: 'yahoo', message_id: '7', mailbox: 'Sent')).to be false
    end

    it 'treats a Yahoo message with a blank first label as INBOX' do
      scope.record([ yahoo_message('7', [ '' ]) ])

      expect(scope.allow?(provider: 'yahoo', message_id: '7', mailbox: 'inbox')).to be true
    end

    it 'allows a raw label that differs from the resolved mailbox name only by case' do
      scope.record([ yahoo_message('7', [ 'Sent Messages' ]) ])

      expect(scope.allow?(provider: 'yahoo', message_id: '7', mailbox: 'sent messages')).to be true
      expect(scope.allow?(provider: 'yahoo', message_id: '7', mailbox: 'Sent')).to be false
    end

    it 'keeps every id when recorded from several threads' do
      threads = Array.new(8) do |thread|
        Thread.new { scope.record(Array.new(25) { |i| gmail_message("t#{thread}-#{i}") }) }
      end
      threads.each(&:join)

      expect(8.times.all? { |t| 25.times.all? { |i| scope.allow?(provider: 'gmail', message_id: "t#{t}-#{i}") } }).to be true
    end
  end

  describe '.refusal' do
    it 'returns an error naming the id and how to recover' do
      expect(described_class.refusal('m9')).to eq(
        error: 'Message m9 was not returned by list_emails or search_emails in this chat. List or search for it first.'
      )
    end
  end

  describe '#bind' do
    include_context 'with gmail configured'

    it 'instantiates scoped tools and passes the other classes through, in order' do
      bound = scope.bind([ Emails::ListTool, Emails::GetTool, Records::TempFileTool ])

      expect(bound).to match([ an_instance_of(Emails::ListTool), an_instance_of(Emails::GetTool), Records::TempFileTool ])
    end

    it 'returns an empty array for no tools' do
      expect(scope.bind([])).to eq([])
    end

    it 'passes a classifier subclass through as a class' do
      classifier = Emails::ClassifyTool.with_classifier(-> { nil })

      expect(scope.bind([ classifier ])).to eq([ classifier ])
    end

    it 'instantiates a subclass of a scoped tool as that subclass' do
      stub_const('BlockedAddLabelsTool', Class.new(Emails::AddLabelsTool))

      expect(scope.bind([ BlockedAddLabelsTool ])).to match([ an_instance_of(BlockedAddLabelsTool) ])
    end

    context 'with listing and fetching stubbed' do
      before do
        allow(Emails).to receive(:list_messages)
          .with('gmail', max_results: 10, after_date: nil, before_date: nil, offset: 0, label: nil)
          .and_return([ gmail_message('m1') ])
        allow(Emails).to receive(:message)
          .with('gmail', 'm1', label: nil)
          .and_return({ id: 'm1', provider: 'gmail', subject: 's' })
      end

      it 'shares the scope between the bound tools' do
        list_tool, get_tool = scope.bind([ Emails::ListTool, Emails::GetTool ])

        list_tool.execute(provider: 'gmail')

        expect(get_tool.execute(provider: 'gmail', message_id: 'm1')).to include(id: 'm1')
        expect(get_tool.execute(provider: 'gmail', message_id: 'm2')).to include(:error)
        expect(Emails).to have_received(:message).once
      end
    end
  end
end
