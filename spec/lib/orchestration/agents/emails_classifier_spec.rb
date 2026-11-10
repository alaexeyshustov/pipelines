require 'rails_helper'

RSpec.describe Orchestration::Agents::EmailsClassifier, :llm, type: :model do
  # LLM_TEST_BACKEND=ollama sends the requests to the local model instead of the stub.
  let(:mistral_url) { LlmTestBackend.completions_url_for('https://api.mistral.ai/v1/chat/completions') }
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

    agent.ask('{"emails":[{"id":"1","subject":"Job offer from Acme"}]}')
  end

  it 'sends the emails agent model (mistral-large-latest by default)' do
    expect(
      a_request(:post, mistral_url).with { |req| JSON.parse(req.body)['model'] == LlmTestBackend.request_model_for('mistral-large-latest') }
    ).to have_been_made
  end

  it 'sends instructions as the system message' do
    expect(
      a_request(:post, mistral_url).with { |req|
        messages = JSON.parse(req.body)['messages']
        system_msg = messages.find { |m| m['role'] == 'system' }
        system_msg['content'].include?('email classifier')
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
