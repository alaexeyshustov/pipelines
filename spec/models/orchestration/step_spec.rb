require 'rails_helper'

RSpec.describe Orchestration::Step do
  it { expect(described_class.table_name).to eq("orchestration_steps") }

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
      build(:orchestration_action_run, status: status)
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

  describe '#previous_sibling' do
    # NOTE: characterizes current behavior. The `steps` association carries a
    # default `order(:position)` (ASC) scope which composes ahead of the
    # method's `order(position: :desc)`, so among several lower steps this
    # returns the lowest-positioned one rather than the adjacent one.
    it 'returns a lower-positioned sibling in the same pipeline' do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      create(:orchestration_step, pipeline: pipeline, position: 2)
      step3 = create(:orchestration_step, pipeline: pipeline, position: 3)
      expect(step3.previous_sibling).to eq(step1)
    end

    it 'returns the adjacent lower step when it is the only lower one' do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2)
      expect(step2.previous_sibling).to eq(step1)
    end

    it 'returns nil for the first step' do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      create(:orchestration_step, pipeline: pipeline, position: 2)
      expect(step1.previous_sibling).to be_nil
    end

    it 'only considers steps within the same pipeline' do
      pipeline = create(:orchestration_pipeline)
      other = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: other, position: 1)
      step = create(:orchestration_step, pipeline: pipeline, position: 2)
      expect(step.previous_sibling).to be_nil
    end
  end

  describe '#next_sibling' do
    it 'returns the nearest step with a higher position' do
      pipeline = create(:orchestration_pipeline)
      step1 = create(:orchestration_step, pipeline: pipeline, position: 1)
      step2 = create(:orchestration_step, pipeline: pipeline, position: 2)
      create(:orchestration_step, pipeline: pipeline, position: 3)
      expect(step1.next_sibling).to eq(step2)
    end

    it 'returns nil for the last step' do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: pipeline, position: 1)
      last = create(:orchestration_step, pipeline: pipeline, position: 2)
      expect(last.next_sibling).to be_nil
    end

    it 'only considers steps within the same pipeline' do
      pipeline = create(:orchestration_pipeline)
      other = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: other, position: 3)
      step = create(:orchestration_step, pipeline: pipeline, position: 2)
      expect(step.next_sibling).to be_nil
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
