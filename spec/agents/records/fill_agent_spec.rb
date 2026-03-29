# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Records::FillAgent, type: :model do
  let(:openai_url) { 'https://api.openai.com/v1/chat/completions' }
  let(:agent) { described_class.create }

  before do
    stub_request(:post, openai_url)
      .to_return(
        status: 200,
        body: {
          id:      'cmpl-test',
          object:  'chat.completion',
          model:   'gpt-5.1',
          choices: [ { index: 0, message: { role: 'assistant', content: '{"rows_updated":0}' }, finish_reason: 'stop' } ],
          usage:   { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    agent.ask('{"emails":[],"destination_table":"application_mails"}')
  end

  it 'sends gpt-5.1 as the model' do
    expect(
      a_request(:post, openai_url).with { |req| JSON.parse(req.body)['model'] == 'gpt-5.1' }
    ).to have_been_made
  end

  it 'sends instructions in the request' do
    expect(
      a_request(:post, openai_url).with { |req|
        messages = JSON.parse(req.body)['messages']
        messages.any? { |m| m['content'].to_s.include?('fill missing values') }
      }
    ).to have_been_made
  end

  it 'sends update and email tools in the request' do
    expect(
      a_request(:post, openai_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[update_rows get_email].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
