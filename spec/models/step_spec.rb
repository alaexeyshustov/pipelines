require 'rails_helper'

RSpec.describe Orchestration::Step, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      step = build(:orchestration_step)
      expect(step).to be_valid
    end

    it 'requires name' do
      step = build(:orchestration_step, name: nil)
      expect(step).not_to be_valid
      expect(step.errors[:name]).not_to be_empty
    end

    it 'requires position' do
      step = build(:orchestration_step, position: nil)
      expect(step).not_to be_valid
      expect(step.errors[:position]).not_to be_empty
    end

    it 'enforces position uniqueness scoped to pipeline' do
      pipeline = create(:orchestration_pipeline)
      create(:orchestration_step, pipeline: pipeline, position: 1)
      duplicate = build(:orchestration_step, pipeline: pipeline, position: 1)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:position]).not_to be_empty
    end

    it 'allows same position in different pipelines' do
      create(:orchestration_step, pipeline: create(:orchestration_pipeline), position: 1)
      other = build(:orchestration_step, pipeline: create(:orchestration_pipeline), position: 1)
      expect(other).to be_valid
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
