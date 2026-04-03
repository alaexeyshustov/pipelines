require 'rails_helper'

RSpec.describe Orchestration::Action do
  describe 'validations' do
    it 'is valid with a name and a valid agent_class' do
      action = build(:orchestration_action)
      expect(action).to be_valid
    end

    it_behaves_like 'requires attribute', :name, :orchestration_action
    it_behaves_like 'requires attribute', :agent_class, :orchestration_action
    it_behaves_like 'rejects invalid attribute value', :agent_class, :orchestration_action, 'NonExistentClass::Whatever'

    it 'accepts a class including Orchestration::Executable' do
      stub_const('MyExecutable', Class.new { include Orchestration::Executable })
      action = build(:orchestration_action, agent_class: 'MyExecutable')
      expect(action).to be_valid
    end

    it 'rejects a class that is neither an agent nor an executable' do
      stub_const('RegularClass', Class.new)
      action = build(:orchestration_action, agent_class: 'RegularClass')
      expect(action).not_to be_valid
      expect(action.errors[:agent_class]).to include(/must inherit from RubyLLM::Agent or include Orchestration::Executable/)
    end
  end

  describe 'associations' do
    it 'blocks deletion when referenced by a step_action' do
      action = create(:orchestration_action)
      create(:orchestration_step_action, action: action)
      action.destroy
      expect(action.errors[:base]).not_to be_empty
      expect(described_class.exists?(action.id)).to be true
    end
  end
end
