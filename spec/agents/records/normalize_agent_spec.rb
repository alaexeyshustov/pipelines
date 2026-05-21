# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Records::NormalizeAgent, type: :model do
  include RecordsAgentHelpers

  let(:agent) { described_class.create }

  before do
    stub_openai_agent_response(content: '{"rows_updated":0}')
    agent.ask('{"records_to_normalize":[],"destination_table":"application_mails","columns_to_normalize":["company"]}')
  end

  it 'sends gpt-5.1 as the model' do
    expect(
      a_request(:post, openai_completions_url).with { |req| JSON.parse(req.body)['model'] == 'gpt-5.1' }
    ).to have_been_made
  end

  it 'sends instructions in the request' do
    expect(
      a_request(:post, openai_completions_url).with { |req|
        messages = JSON.parse(req.body)['messages']
        messages.any? { |m| m['content'].to_s.include?('database record normalizer') }
      }
    ).to have_been_made
  end

  it 'sends normalization tools in the request' do
    expect(
      a_request(:post, openai_completions_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[list_rows read_rows update_rows read_schema search_similar].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
