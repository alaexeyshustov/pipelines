require 'rails_helper'

RSpec.describe Emails::FilterAgent, type: :model do
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

    agent.ask('{"topic":"job applications","emails":[]}')
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
        system_msg['content'].include?('email filtering expert')
      }
    ).to have_been_made
  end

  it 'sends temp_file as a tool' do
    expect(
      a_request(:post, mistral_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        tool_names.include?('temp_file')
      }
    ).to have_been_made
  end
end
