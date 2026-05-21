# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Records::ReconcileAgent, type: :model do
  include RecordsAgentHelpers

  let(:agent) { described_class.create }

  before do
    stub_openai_agent_response(content: 'No changes needed.')
    agent.ask('[]')
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
        messages.any? { |m| m['content'].to_s.include?('job application lifecycle tracker') }
      }
    ).to have_been_made
  end

  it 'sends database tools as context' do
    expect(
      a_request(:post, openai_completions_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[read_rows insert_rows].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
