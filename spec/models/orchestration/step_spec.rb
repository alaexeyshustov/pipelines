require 'rails_helper'

RSpec.describe Orchestration::Step do
  describe 'validations' do
    it 'is valid with required attributes' do
      step = build(:orchestration_step)
      expect(step).to be_valid
    end

    it_behaves_like 'requires attribute', :name, :orchestration_step
    it_behaves_like 'requires attribute', :position, :orchestration_step
    it_behaves_like 'enforces position uniqueness scoped to',
                    :orchestration_step, :pipeline, :orchestration_pipeline
  end

  describe '.derive_status' do
    def stub_run(status)
      instance_double(Orchestration::ActionRun, status: status)
    end

    it 'returns pending when action_runs is empty' do
      expect(described_class.derive_status([])).to eq('pending')
    end

    it 'returns completed when all action_runs are completed' do
      runs = [ stub_run('completed'), stub_run('completed') ]
      expect(described_class.derive_status(runs)).to eq('completed')
    end

    it 'returns failed when any action_run is failed' do
      runs = [ stub_run('completed'), stub_run('failed') ]
      expect(described_class.derive_status(runs)).to eq('failed')
    end

    it 'returns running when any action_run is running and none failed' do
      runs = [ stub_run('completed'), stub_run('running') ]
      expect(described_class.derive_status(runs)).to eq('running')
    end

    it 'returns failed over running when both are present' do
      runs = [ stub_run('failed'), stub_run('running') ]
      expect(described_class.derive_status(runs)).to eq('failed')
    end

    it 'returns pending when all action_runs are pending' do
      runs = [ stub_run('pending'), stub_run('pending') ]
      expect(described_class.derive_status(runs)).to eq('pending')
    end
  end

  describe 'associations' do
    it 'destroys step_actions when step is destroyed' do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline)
      action = create(:orchestration_action)
      create(:orchestration_step_action, step: step, action: action, position: 1)
      expect { step.destroy }.to change(Orchestration::StepAction, :count).by(-1)
    end

    it 'returns actions through step_actions' do
      pipeline = create(:orchestration_pipeline)
      step = create(:orchestration_step, pipeline: pipeline)
      action = create(:orchestration_action)
      create(:orchestration_step_action, step: step, action: action, position: 1)
      expect(step.actions).to include(action)
    end

    it 'orders steps by position' do
      pipeline = create(:orchestration_pipeline)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      expect(pipeline.steps.to_a).to eq([ step1, step2 ])
    end
  end
end
