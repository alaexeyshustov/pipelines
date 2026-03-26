require 'rails_helper'

RSpec.describe Orchestration::StepAction do
  describe 'validations' do
    it 'is valid with required attributes' do
      step_action = build(:orchestration_step_action)
      expect(step_action).to be_valid
    end

    it_behaves_like 'requires attribute', :position, :orchestration_step_action
    it_behaves_like 'enforces position uniqueness scoped to',
                    :orchestration_step_action, :step, :orchestration_step
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
