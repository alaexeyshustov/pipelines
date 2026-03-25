require 'rails_helper'

RSpec.describe Emails::SearchTool do
  subject(:tool) { described_class.new }

  include_context 'with gmail configured'

  before do
    stub_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages(?!\/)/)
      .to_return(
        status: 200,
        body: { messages: [ { id: 'msg1', threadId: 'thread1' } ], resultSizeEstimate: 1 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/msg1/)
      .to_return(
        status: 200,
        body: gmail_message_json(id: 'msg1', subject: 'Interview invitation'),
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns matching emails' do
    result = tool.execute(provider: 'gmail', query: 'subject:interview')
    expect(result).to be_an(Array)
    expect(result.first).to include(id: 'msg1')
  end

  it 'passes the query string to the API' do
    tool.execute(provider: 'gmail', query: 'from:recruiter@acme.com')
    expect(
      a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages(?!\/)/).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['q'] == 'from:recruiter@acme.com'
      }
    ).to have_been_made
  end

  it 'respects max_results' do
    tool.execute(provider: 'gmail', query: 'job', max_results: 25)
    expect(
      a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages(?!\/)/).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['maxResults'] == '25'
      }
    ).to have_been_made
  end
end
