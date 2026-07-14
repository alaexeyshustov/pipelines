# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipeline::ApplicationsWorkflow do
  subject(:workflow) { described_class.new(model: 'mistral-large-latest', logger: logger, date: Date.new(2026, 3, 15)) }

  let(:logger) { Logger.new(IO::NULL) }
  let(:agent_steps) { Pipeline::ApplicationsWorkflow::AgentSteps.new(model: 'mistral-large-latest') }
  let(:fetcher) { Pipeline::EmailProviderFetcher.new(date: Date.new(2026, 3, 15)) }

  before do
    allow(Pipeline::EmailProviderFetcher).to receive(:new).and_return(fetcher)
    allow(Pipeline::ApplicationsWorkflow::AgentSteps).to receive(:new).and_return(agent_steps)
  end

  describe '#run' do
    it 'returns no_emails_fetched when no emails were fetched' do
      allow(fetcher).to receive(:call).and_return([])

      expect(workflow.run).to eq(status: 'no_emails_fetched')
    end

    it 'returns no_filtered_emails when nothing survives filtering' do
      allow(fetcher).to receive(:call).and_return([ { 'id' => '1' } ])
      allow(agent_steps).to receive_messages(classify_email: { 'results' => [] }, filter_emails: { 'results' => [] })

      expect(workflow.run).to eq(status: 'no_filtered_emails')
    end

    it 'returns no_mapped_emails when nothing survives mapping' do
      allow(fetcher).to receive(:call).and_return([ { 'id' => '1' } ])
      allow(agent_steps).to receive_messages(classify_email: { 'results' => [] }, filter_emails: { 'results' => [ { 'id' => '1' } ] }, map_emails: { 'emails' => [] })

      expect(workflow.run).to eq(status: 'no_mapped_emails')
    end

    it 'runs the full pipeline and returns the reconciliation result when no GIST_ID is set' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GIST_ID', nil).and_return(nil)

      allow(fetcher).to receive(:call).and_return([ { 'id' => '1' } ])
      allow(agent_steps).to receive_messages(classify_email: { 'results' => [] }, filter_emails: { 'results' => [ { 'id' => '1' } ] }, map_emails: { 'emails' => [ { 'id' => '1' } ] }, store_mapped_emails: { 'ids' => [] }, normalize_stored_emails: {}, reconcile_emails_to_interviews: { 'reconciled' => true })

      result = workflow.run

      expect(result).to eq(status: 'test_complete', model_used: 'mistral-large-latest', result: { 'reconciled' => true })
      expect(agent_steps).to have_received(:reconcile_emails_to_interviews).with(emails: [])
    end
  end

  describe '#step8_upload_csv_gist' do
    it 'uploads via GistExportService and returns ok/message' do
      service = Interviews::GistExportService.new(ids: nil, gist_id: 'abc123')
      result  = Interviews::GistExportService::Result.new(ok: true, message: 'uploaded')
      allow(Interviews::GistExportService).to receive(:new).with(ids: nil, gist_id: 'abc123').and_return(service)
      allow(service).to receive(:call).and_return(result)

      expect(workflow.step8_upload_csv_gist(gist_id: 'abc123')).to eq('ok' => true, 'message' => 'uploaded')
    end
  end
end
