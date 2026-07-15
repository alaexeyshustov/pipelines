# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipeline::ApplicationsWorkflow::AgentSteps do
  include RecordsAgentHelpers

  subject(:agent_steps) { described_class.new(model: 'mistral-large-latest') }

  describe '#classify_email' do
    it 'sends email id and subject to the classifier and returns parsed content' do
      stub_mistral_agent_response(content: '{"results":[{"id":"1","tags":["job"]}]}')

      result = agent_steps.classify_email(emails: [ { 'id' => '1', 'subject' => 'Job offer', 'from' => 'ignored' } ])

      expect(result).to eq('results' => [ { 'id' => '1', 'tags' => [ 'job' ] } ])
      expect(
        a_request(:post, mistral_completions_url).with { |req|
          body = JSON.parse(JSON.parse(req.body)['messages'].find { |m| m['role'] == 'user' }['content'])
          body['emails'] == [ { 'id' => '1', 'subject' => 'Job offer' } ]
        }
      ).to have_been_made
    end
  end

  describe '#filter_emails' do
    it 'merges tags onto each email by id before sending to the filter' do
      stub_mistral_agent_response(content: '{"results":[]}')

      agent_steps.filter_emails(emails: [ { 'id' => '1' } ], tags: [ { 'id' => '1', 'tags' => [ 'job' ] } ])

      expect(
        a_request(:post, mistral_completions_url).with { |req|
          body = JSON.parse(JSON.parse(req.body)['messages'].find { |m| m['role'] == 'user' }['content'])
          body['emails'] == [ { 'id' => '1', 'tags' => [ 'job' ] } ] && body['topic'] == 'job applications'
        }
      ).to have_been_made
    end
  end

  describe '#map_emails' do
    it 'returns the mapper content with string keys' do
      stub_mistral_agent_response(content: '{"emails":[{"id":"1"}]}')

      result = agent_steps.map_emails(emails: [ { 'id' => '1' } ])

      expect(result).to eq('emails' => [ { 'id' => '1' } ])
    end

    it 'returns an empty hash when the mapper content is not a hash' do
      stub_mistral_agent_response(content: '[]')

      expect(agent_steps.map_emails(emails: [])).to eq({})
    end
  end

  describe '#store_mapped_emails' do
    it 'returns the storer content with string keys' do
      stub_mistral_agent_response(content: '{"ids":[1,2]}')

      result = agent_steps.store_mapped_emails(emails: [ { 'id' => '1' } ])

      expect(result).to eq('ids' => [ 1, 2 ])
    end
  end

  describe '#normalize_stored_emails' do
    it 'sends the destination table and columns to normalize' do
      stub_mistral_agent_response(content: '{"normalized":true}')

      agent_steps.normalize_stored_emails(emails: [ { 'id' => '1' } ])

      expect(
        a_request(:post, mistral_completions_url).with { |req|
          body = JSON.parse(JSON.parse(req.body)['messages'].find { |m| m['role'] == 'user' }['content'])
          body['destination_table'] == 'application_mails' && body['columns_to_normalize'] == [ 'company', 'job_title' ]
        }
      ).to have_been_made
    end
  end

  describe '#reconcile_emails_to_interviews' do
    it 'returns an empty hash without making a request when emails are empty' do
      expect(agent_steps.reconcile_emails_to_interviews(emails: [])).to eq({})
      expect(a_request(:post, mistral_completions_url)).not_to have_been_made
    end

    it 'sends the destination table and matching columns when emails are present' do
      stub_mistral_agent_response(content: '{"reconciled":true}')

      agent_steps.reconcile_emails_to_interviews(emails: [ { 'id' => '1' } ])

      expect(
        a_request(:post, mistral_completions_url).with { |req|
          body = JSON.parse(JSON.parse(req.body)['messages'].find { |m| m['role'] == 'user' }['content'])
          body['destination_table'] == 'interviews' && body['matching_columns'] == [ 'company', 'job_title' ]
        }
      ).to have_been_made
    end
  end
end
