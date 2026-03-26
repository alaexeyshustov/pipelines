# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Records::NormalizeAgent, type: :model do
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

    agent.ask('{"records_to_normalize":[],"destination_table":"application_mails","columns_to_normalize":["company"]}')
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
        messages.any? { |m| m['content'].to_s.include?('database record normalizer') }
      }
    ).to have_been_made
  end

  it 'sends normalization tools in the request' do
    expect(
      a_request(:post, openai_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[list_rows read_rows update_rows read_schema search_similar].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
