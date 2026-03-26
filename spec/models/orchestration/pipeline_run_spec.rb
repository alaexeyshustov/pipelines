require 'rails_helper'

RSpec.describe Orchestration::PipelineRun do
  describe 'validations' do
    it 'is valid with required attributes' do
      run = build(:orchestration_pipeline_run)
      expect(run).to be_valid
    end

    it_behaves_like 'requires attribute', :status, :orchestration_pipeline_run
    it_behaves_like 'rejects invalid attribute value', :status, :orchestration_pipeline_run, 'invalid'
    it_behaves_like 'accepts valid statuses', :orchestration_pipeline_run, %w[pending running completed failed]
    it_behaves_like 'rejects invalid attribute value', :triggered_by, :orchestration_pipeline_run, 'robot'

    it 'accepts nil triggered_by' do
      run = build(:orchestration_pipeline_run, triggered_by: nil)
      expect(run).to be_valid
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
