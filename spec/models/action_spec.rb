require 'rails_helper'

RSpec.describe Orchestration::Action, type: :model do
  describe 'validations' do
    it 'is valid with a name and a valid agent_class' do
      action = build(:orchestration_action)
      expect(action).to be_valid
    end

    it 'requires name' do
      action = build(:orchestration_action, name: nil)
      expect(action).not_to be_valid
      expect(action.errors[:name]).not_to be_empty
    end

    it 'requires agent_class' do
      action = build(:orchestration_action, agent_class: nil)
      expect(action).not_to be_valid
      expect(action.errors[:agent_class]).not_to be_empty
    end

    it 'rejects agent_class that does not exist as a constant' do
      action = build(:orchestration_action, agent_class: 'NonExistentClass::Whatever')
      expect(action).not_to be_valid
      expect(action.errors[:agent_class]).not_to be_empty
    end

    it 'rejects agent_class that does not inherit from RubyLLM::Agent' do
      action = build(:orchestration_action, agent_class: 'ApplicationRecord')
      expect(action).not_to be_valid
      expect(action.errors[:agent_class]).not_to be_empty
    end
  end

  describe 'associations' do
    it 'blocks deletion when referenced by a step_action' do
      action = create(:orchestration_action)
      create(:orchestration_step_action, action: action)
      action.destroy
      expect(action.errors[:base]).not_to be_empty
      expect(Orchestration::Action.exists?(action.id)).to be true
    end
  end
end
