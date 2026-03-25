require 'rails_helper'

RSpec.describe Emails::AddLabelsTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'

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
end
