require 'rails_helper'

RSpec.describe ClassifyEmailsTool do
  subject(:tool) { described_class.new }

  let(:mistral_url) { 'https://api.mistral.ai/v1/chat/completions' }
  let(:emails)      { [ { 'id' => 'msg1', 'subject' => 'Interview invitation from Acme' } ] }

  before do
    stub_request(:post, mistral_url)
      .to_return(
        status: 200,
        body: {
          id: 'cmpl-test',
          object: 'chat.completion',
          model: 'mistral-large-latest',
          choices: [ {
            index: 0,
            message: {
              role: 'assistant',
              content: '{"results":[{"id":"msg1","subject":"Interview invitation from Acme","tags":["interview","job"]}]}'
            },
            finish_reason: 'stop'
          } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the classifier response from the agent' do
    result = tool.execute(emails: emails)
    expect(result).to be_present
  end

  it 'sends the email subjects to the Mistral API' do
    tool.execute(emails: emails)
    expect(
      a_request(:post, mistral_url).with { |req|
        messages = JSON.parse(req.body)['messages']
        messages.any? { |m| m['content'].to_s.include?('Interview invitation from Acme') }
      }
    ).to have_been_made
  end

  it 'returns empty when given no emails' do
    result = tool.execute(emails: [])
    expect(result).to be_blank
  end

  it 'returns empty when given nil' do
    result = tool.execute(emails: nil)
    expect(result).to be_blank
  end

  it 'skips non-hash entries without raising' do
    expect { tool.execute(emails: [ 'not a hash', nil ]) }.not_to raise_error
  end
end
