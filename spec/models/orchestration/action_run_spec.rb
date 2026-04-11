require 'rails_helper'

RSpec.describe Orchestration::ActionRun do
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
end
