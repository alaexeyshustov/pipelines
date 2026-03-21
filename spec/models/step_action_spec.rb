require 'rails_helper'

RSpec.describe Orchestration::StepAction, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      step_action = build(:orchestration_step_action)
      expect(step_action).to be_valid
    end

    it 'requires position' do
      step_action = build(:orchestration_step_action, position: nil)
      expect(step_action).not_to be_valid
      expect(step_action.errors[:position]).not_to be_empty
    end

    it 'enforces position uniqueness scoped to step' do
      step = create(:orchestration_step)
      create(:orchestration_step_action, step: step, position: 1)
      duplicate = build(:orchestration_step_action, step: step, position: 1)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:position]).not_to be_empty
    end

    it 'allows same position in different steps' do
      create(:orchestration_step_action, step: create(:orchestration_step), position: 1)
      other = build(:orchestration_step_action, step: create(:orchestration_step), position: 1)
      expect(other).to be_valid
    end
  end

  describe 'associations' do
    it 'orders step_actions by position' do
      step = create(:orchestration_step)
      action_a = create(:orchestration_action)
      action_b = create(:orchestration_action)
      sa2 = create(:orchestration_step_action, step: step, action: action_a, position: 2)
      sa1 = create(:orchestration_step_action, step: step, action: action_b, position: 1)
      expect(step.step_actions.to_a).to eq([ sa1, sa2 ])
    end
  end
end
