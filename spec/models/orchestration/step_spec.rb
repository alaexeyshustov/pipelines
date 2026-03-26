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
