require 'rails_helper'

RSpec.describe Orchestration::PipelineRun, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      run = build(:orchestration_pipeline_run)
      expect(run).to be_valid
    end

    it 'requires status' do
      run = build(:orchestration_pipeline_run, status: nil)
      expect(run).not_to be_valid
      expect(run.errors[:status]).not_to be_empty
    end

    it 'rejects invalid status' do
      run = build(:orchestration_pipeline_run, status: 'invalid')
      expect(run).not_to be_valid
      expect(run.errors[:status]).not_to be_empty
    end

    it 'accepts valid statuses' do
      %w[pending running completed failed].each do |s|
        run = build(:orchestration_pipeline_run, status: s)
        expect(run).to be_valid
      end
    end

    it 'accepts nil triggered_by' do
      run = build(:orchestration_pipeline_run, triggered_by: nil)
      expect(run).to be_valid
    end

    it 'rejects invalid triggered_by' do
      run = build(:orchestration_pipeline_run, triggered_by: 'robot')
      expect(run).not_to be_valid
      expect(run.errors[:triggered_by]).not_to be_empty
    end

    it 'contains expected STATUSES' do
      expect(Orchestration::PipelineRun::STATUSES).to eq(%w[pending running completed failed])
    end
  end

  describe 'associations' do
    it 'destroys action_runs when pipeline_run is destroyed' do
      pipeline_run = create(:orchestration_pipeline_run)
      step = create(:orchestration_step)
      step_action = create(:orchestration_step_action, step: step, position: 1)
      create(:orchestration_action_run, pipeline_run: pipeline_run, step_action: step_action)
      expect { pipeline_run.destroy }.to change(Orchestration::ActionRun, :count).by(-1)
    end
  end
end
