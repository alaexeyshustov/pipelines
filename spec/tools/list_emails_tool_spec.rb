require 'rails_helper'

RSpec.describe ListEmailsTool do
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
        body: gmail_message_json(id: 'msg1', subject: 'Job offer at Acme'),
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns emails from the provider' do
    result = tool.execute(provider: 'gmail')
    expect(result).to be_an(Array)
    expect(result.first).to include(id: 'msg1', subject: 'Job offer at Acme')
  end

  it 'requests the correct max_results' do
    tool.execute(provider: 'gmail', max_results: 50)
    expect(
      a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages(?!\/)/).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['maxResults'] == '50'
      }
    ).to have_been_made
  end

  it 'passes after_date as a query filter' do
    tool.execute(provider: 'gmail', after_date: '2026-01-01')
    expect(
      a_request(:get, /gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages(?!\/)/).with { |req|
        URI.decode_www_form(URI.parse(req.uri).query.to_s).to_h['q']&.include?('after:')
      }
    ).to have_been_made
  end
end
