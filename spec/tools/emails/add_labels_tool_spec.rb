require 'rails_helper'

RSpec.describe Emails::AddLabelsTool do
  subject(:tool) { described_class.new(message_scope: scope) }

  include_context 'with gmail configured'

  let(:scope) do
    Emails::MessageScope.new.tap do |message_scope|
      message_scope.record([
        { id: 'msg1', provider: 'gmail', labels: [ 'INBOX' ] },
        { id: '101', provider: 'yahoo', labels: [ 'INBOX' ] }
      ])
    end
  end

  before do
    stub_request(:post, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg1\/modify/)
      .to_return(
        status: 200,
        body: { id: 'msg1', labelIds: [ 'INBOX', 'Label_1' ] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the modified message with updated labels' do
    result = tool.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ 'Label_1' ])
    expect(result).to include(id: 'msg1', labels: include('Label_1'))
  end

  it 'posts label_ids to the modify endpoint' do
    tool.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ 'STARRED' ])
    expect(
      a_request(:post, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg1\/modify/).with { |req|
        JSON.parse(req.body)['addLabelIds'].include?('STARRED')
      }
    ).to have_been_made
  end

  it 'forwards Yahoo mailbox context when adding IMAP flags' do
    allow(Emails).to receive(:modify_labels).and_return(message_id: 101, added: [ '\\Flagged' ], removed: [])

    tool.execute(provider: 'yahoo', message_id: '101', label_ids: [ '\\Flagged' ], mailbox: 'Inbox')

    expect(Emails).to have_received(:modify_labels)
      .with('yahoo', '101', add: [ '\\Flagged' ], source_mailbox: 'Inbox')
  end

  describe 'message scope' do
    before { allow(Emails).to receive(:modify_labels).and_return(message_id: 'x', added: [], removed: []) }

    it 'refuses every id on an unscoped tool' do
      result = described_class.new.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ 'STARRED' ])

      expect(result).to include(error: match(/list_emails|search_emails/))
      expect(Emails).not_to have_received(:modify_labels)
    end

    it 'refuses an id outside the scope' do
      result = tool.execute(provider: 'gmail', message_id: 'msg2', label_ids: [ 'STARRED' ])

      expect(result).to include(error: match(/list_emails|search_emails/))
      expect(Emails).not_to have_received(:modify_labels)
    end

    it 'refuses a Yahoo uid from another mailbox' do
      result = tool.execute(provider: 'yahoo', message_id: '101', label_ids: [ '\\Flagged' ], mailbox: 'Archive')

      expect(result).to include(:error)
      expect(Emails).not_to have_received(:modify_labels)
    end

    it 'allows a listed Yahoo uid in the default mailbox' do
      tool.execute(provider: 'yahoo', message_id: '101', label_ids: [ '\\Flagged' ])

      expect(Emails).to have_received(:modify_labels).with('yahoo', '101', add: [ '\\Flagged' ], source_mailbox: 'INBOX')
    end

    it 'treats a blank Yahoo mailbox as INBOX for the scope check' do
      tool.execute(provider: 'yahoo', message_id: '101', label_ids: [ '\\Flagged' ], mailbox: '')

      expect(Emails).to have_received(:modify_labels).with('yahoo', '101', add: [ '\\Flagged' ], source_mailbox: '')
    end

    it 'still returns the label-policy error for an in-scope id' do
      result = tool.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ 'TRASH' ])

      expect(result).to include(error: match(/Labels not allowed/))
      expect(Emails).not_to have_received(:modify_labels)
    end
  end

  describe 'label policy' do
    before { allow(Emails).to receive(:modify_labels).and_return(message_id: 'msg1', added: [], removed: []) }

    [ 'TRASH', 'trash', 'SPAM', 'spam', 'Spam', '\\Deleted', '\\deleted', '\\Answered', '\\Draft' ].each do |label|
      it "rejects #{label.inspect} and does not modify the message" do
        result = tool.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ label ])

        expect(result).to include(:error)
        expect(Emails).not_to have_received(:modify_labels)
      end
    end

    it 'applies none of the labels when any one is rejected' do
      result = tool.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ 'STARRED', 'TRASH' ])

      expect(result).to include(:error)
      expect(Emails).not_to have_received(:modify_labels)
    end

    [ 'STARRED', '\\Flagged', '\\Seen', 'Label_1' ].each do |label|
      it "allows #{label.inspect}" do
        result = tool.execute(provider: 'gmail', message_id: 'msg1', label_ids: [ label ])

        expect(result).not_to include(:error)
        expect(Emails).to have_received(:modify_labels).with('gmail', 'msg1', add: [ label ], source_mailbox: 'INBOX')
      end
    end
  end
end
