require 'rails_helper'

RSpec.describe Emails::SearchTool do
  subject(:tool) { described_class.new(message_scope: scope) }

  let(:scope) { Emails::MessageScope.new }

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

  it 'passes offset through to Emails.search_messages' do
    allow(Emails).to receive(:search_messages).and_return([])

    tool.execute(provider: 'gmail', query: 'job', max_results: 5, offset: 20)

    expect(Emails).to have_received(:search_messages)
      .with('gmail', 'job', max_results: 5, label: nil, offset: 20)
  end

  it 'records the returned messages in the scope without changing the result' do
    result = tool.execute(provider: 'gmail', query: 'job')

    expect(result.first).to include(id: 'msg1')
    expect(scope.allow?(provider: 'gmail', message_id: 'msg1')).to be true
    expect(scope.allow?(provider: 'gmail', message_id: 'other')).to be false
  end

  it 'passes a non-array result through and records nothing' do
    allow(Emails).to receive(:search_messages)
      .with('gmail', 'job', max_results: 10, offset: 0, label: nil)
      .and_return({ error: 'boom' })

    expect(tool.execute(provider: 'gmail', query: 'job')).to eq(error: 'boom')
    expect(scope.allow?(provider: 'gmail', message_id: 'msg1')).to be false
  end

  it 'builds without arguments' do
    expect { described_class.new }.not_to raise_error
  end
end
