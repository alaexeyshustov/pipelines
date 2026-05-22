require 'rails_helper'

RSpec.describe Orchestration::ActionRun do
  it { expect(described_class.table_name).to eq("orchestration_action_runs") }

  describe 'validations' do
    it 'is valid with required attributes' do
      action_run = build(:orchestration_action_run)
      expect(action_run).to be_valid
    end

    it_behaves_like 'requires attribute', :status, :orchestration_action_run
    it_behaves_like 'rejects invalid attribute value', :status, :orchestration_action_run, 'bogus'
    it_behaves_like 'accepts valid statuses', :orchestration_action_run, %w[pending running completed failed]

    it 'contains expected STATUSES' do
      expect(Orchestration::ActionRun::STATUSES).to eq(%w[pending running completed failed])
    end
  end

  describe 'associations' do
    it 'belongs to pipeline_run and step_action' do
      action_run = create(:orchestration_action_run)
      expect(action_run.pipeline_run).to be_a(Orchestration::PipelineRun)
      expect(action_run.step_action).to be_a(Orchestration::StepAction)
    end

    it 'optionally belongs to a chat' do
      action_run = create(:orchestration_action_run)
      expect(action_run.chat).to be_nil
    end

    it 'accepts a chat association' do
      chat = create(:chat)
      action_run = create(:orchestration_action_run, chat: chat)
      expect(action_run.chat).to eq(chat)
    end
  end

  describe '#ground_truth' do
    it 'returns the full output value' do
      action_run = create(:orchestration_action_run, output: { 'classification' => 'offer' })
      expect(action_run.ground_truth).to eq({ 'classification' => 'offer' })
    end

    it 'returns nil when output is blank' do
      action_run = create(:orchestration_action_run, output: nil)
      expect(action_run.ground_truth).to be_nil
    end
  end

  describe '#index_attributes' do
    it 'returns hash with status and action name' do
      action_run = create(:orchestration_action_run, status: 'completed')
      result = action_run.index_attributes
      expect(result).to include(status: 'completed')
      expect(result).to have_key(:action)
    end
  end

  describe '#show_attributes' do
    it 'returns hash including input, output, status, and error_details' do # rubocop:disable RSpec/MultipleExpectations
      action_run = create(:orchestration_action_run,
                          status: 'completed',
                          input: { 'email' => 'test' },
                          output: { 'result' => 'ok' },
                          error_details: { 'category' => 'provider_http_error' })
      result = action_run.show_attributes
      expect(result).to include(status: 'completed')
      expect(result).to have_key(:input)
      expect(result).to have_key(:output)
      expect(result).to have_key(:error_details)
    end
  end

  describe '#to_llm_context' do
    it 'returns hash with input, action, status, and agent_snapshot' do # rubocop:disable RSpec/MultipleExpectations
      action_run = create(:orchestration_action_run, input: { 'email' => 'test body' }, agent_snapshot: { 'model' => 'mistral' })
      result = action_run.to_llm_context
      expect(result).to have_key(:input)
      expect(result).to have_key(:action)
      expect(result).to have_key(:status)
      expect(result).to have_key(:agent_snapshot)
      expect(result[:agent_snapshot]).to eq({ 'model' => 'mistral' })
    end
  end
end
