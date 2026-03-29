# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Emails::MappingAgent, type: :model do
  let(:mistral_url) { 'https://api.mistral.ai/v1/chat/completions' }
  let(:agent) { described_class.create }

  before do
    stub_request(:post, mistral_url)
      .to_return(
        status: 200,
        body: {
          id:      'cmpl-test',
          object:  'chat.completion',
          model:   'mistral-large-latest',
          choices: [ { index: 0, message: { role: 'assistant', content: '{}' }, finish_reason: 'stop' } ],
          usage:   { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    agent.ask('{"emails":[]}')
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
        system_msg['content'].include?('call get_email to fetch its full content')
      }
    ).to have_been_made
  end

  it 'sends get_email and temp_file tools in the request' do
    expect(
      a_request(:post, mistral_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[get_email temp_file].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
