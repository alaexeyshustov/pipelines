require 'rails_helper'

RSpec.describe EmailFetchAgent, type: :model do
  let(:mistral_url) { 'https://api.mistral.ai/v1/chat/completions' }
  let(:agent) { described_class.create }

  before do
    stub_request(:post, mistral_url)
      .to_return(
        status: 200,
        body: {
          id: 'cmpl-test',
          object: 'chat.completion',
          model: 'mistral-large-latest',
          choices: [ { index: 0, message: { role: 'assistant', content: '{"results":[]}' }, finish_reason: 'stop' } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    agent.ask('{"provider":"gmail","after_date":"2026-01-01"}')
  end

  it 'sends mistral-large-latest as the model' do
    expect(
      a_request(:post, mistral_url).with { |req| JSON.parse(req.body)['model'] == 'mistral-large-latest' }
    ).to have_been_made
  end

  it 'sends instructions as the system message' do
    expect(
      a_request(:post, mistral_url).with { |req|
        messages = JSON.parse(req.body)['messages']
        system_msg = messages.find { |m| m['role'] == 'system' }
        system_msg['content'].include?('email fetcher')
      }
    ).to have_been_made
  end

  it 'sends email tools as context' do
    expect(
      a_request(:post, mistral_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[list_emails search_emails get_email manage_temp_file].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
