# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orchestration::Agents::RecordsStorer, type: :model do
  include RecordsAgentHelpers

  let(:agent) { described_class.create }

  before do
    stub_mistral_agent_response(content: '{"rows_inserted":0}')
    agent.ask('{"label":"applications","table":"application_mails","emails":[]}')
  end

  it 'sends mistral-large-latest as the model' do
    expect(
      a_request(:post, mistral_completions_url).with { |req| JSON.parse(req.body)['model'] == 'mistral-large-latest' }
    ).to have_been_made
  end

  it 'sends instructions as the system message' do
    expect(
      a_request(:post, mistral_completions_url).with { |req|
        messages = JSON.parse(req.body)['messages']
        system_msg = messages.find { |m| m['role'] == 'system' }
        system_msg['content'].include?('emails processor') &&
          system_msg['content'].include?('Yahoo: use the Yahoo folder name itself in label_ids') &&
          system_msg['content'].include?('do not pass the destination label/folder as mailbox')
      }
    ).to have_been_made
  end

  it 'sends labeling and storage tools as context' do
    expect(
      a_request(:post, mistral_completions_url).with { |req|
        tool_names = JSON.parse(req.body)['tools'].map { |t| t.dig('function', 'name') }
        %w[get_labels create_label add_labels insert_rows read_schema get_email].all? { |t| tool_names.include?(t) }
      }
    ).to have_been_made
  end
end
