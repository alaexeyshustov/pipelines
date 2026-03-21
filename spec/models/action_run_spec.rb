require 'rails_helper'

RSpec.describe Orchestration::ActionRun, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      action_run = build(:orchestration_action_run)
      expect(action_run).to be_valid
    end

    it 'requires status' do
      action_run = build(:orchestration_action_run, status: nil)
      expect(action_run).not_to be_valid
      expect(action_run.errors[:status]).not_to be_empty
    end

    it 'rejects invalid status' do
      action_run = build(:orchestration_action_run, status: 'bogus')
      expect(action_run).not_to be_valid
      expect(action_run.errors[:status]).not_to be_empty
    end

    it 'accepts valid statuses' do
      %w[pending running completed failed].each do |s|
        action_run = build(:orchestration_action_run, status: s)
        expect(action_run).to be_valid
      end
    end

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
  end
end
