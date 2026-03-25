require 'rails_helper'

RSpec.describe Emails::GetTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'

  before do
    stub_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg_abc/)
      .to_return(
        status: 200,
        body: gmail_message_json(id: 'msg_abc', subject: 'Your application status', from: 'hr@company.com'),
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the email content' do
    result = tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(result).to include(id: 'msg_abc', subject: 'Your application status', from: 'hr@company.com')
  end

  it 'fetches the message with full format' do
    tool.execute(provider: 'gmail', message_id: 'msg_abc')
    expect(
      a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg_abc/).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['format'] == 'full'
      }
    ).to have_been_made
  end
end
