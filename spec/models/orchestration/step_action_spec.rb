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

    describe 'output_key' do
      it 'is required' do
        step_action = build(:orchestration_step_action, output_key: nil)
        expect(step_action).not_to be_valid
        expect(step_action.errors[:output_key]).to include(/can't be blank/)
      end

      it 'accepts lowercase letters, digits, and underscores starting with a letter' do
        step_action = build(:orchestration_step_action, output_key: 'classify_emails_v2')
        expect(step_action).to be_valid
      end

      it 'rejects keys starting with a digit' do
        step_action = build(:orchestration_step_action, output_key: '1emails')
        expect(step_action).not_to be_valid
        expect(step_action.errors[:output_key]).to be_present
      end

      it 'rejects keys with uppercase letters' do
        step_action = build(:orchestration_step_action, output_key: 'ClassifyEmails')
        expect(step_action).not_to be_valid
        expect(step_action.errors[:output_key]).to be_present
      end

      it 'rejects keys with hyphens' do
        step_action = build(:orchestration_step_action, output_key: 'classify-emails')
        expect(step_action).not_to be_valid
        expect(step_action.errors[:output_key]).to be_present
      end

      it 'rejects keys starting with an underscore (reserved namespace)' do
        step_action = build(:orchestration_step_action, output_key: '_initial')
        expect(step_action).not_to be_valid
        expect(step_action.errors[:output_key]).to be_present
      end

      it 'is unique within a step' do
        step = create(:orchestration_step)
        create(:orchestration_step_action, step: step, output_key: 'classify_emails', position: 1)
        duplicate = build(:orchestration_step_action, step: step, output_key: 'classify_emails', position: 2)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:output_key]).to include(/has already been taken/)
      end

      it 'allows the same output_key in different steps' do
        pipeline = create(:orchestration_pipeline)
        step_a   = create(:orchestration_step, pipeline: pipeline, position: 1)
        step_b   = create(:orchestration_step, pipeline: pipeline, position: 2)
        create(:orchestration_step_action, step: step_a, output_key: 'classify_emails', position: 1)
        twin = build(:orchestration_step_action, step: step_b, output_key: 'classify_emails', position: 1)
        expect(twin).to be_valid
      end
    end

    describe 'output_key immutability' do
      it 'allows changing output_key when no ActionRun exists' do
        step_action = create(:orchestration_step_action, output_key: 'before_run')
        step_action.output_key = 'after_edit'
        expect(step_action).to be_valid
      end

      it 'rejects changing output_key once an ActionRun exists' do
        step_action = create(:orchestration_step_action, output_key: 'classify_emails')
        create(:orchestration_action_run, step_action: step_action)
        step_action.output_key = 'something_else'
        expect(step_action).not_to be_valid
        expect(step_action.errors[:output_key]).to include(/cannot be changed once a run exists/)
      end

      it 'allows persisting the same output_key after a run exists' do
        step_action = create(:orchestration_step_action, output_key: 'classify_emails')
        create(:orchestration_action_run, step_action: step_action)
        expect { step_action.update!(position: step_action.position + 10) }.not_to raise_error
      end
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

  describe 'input_mapping column' do
    it 'round-trips a JSON object' do
      mapping = { 'emails' => { 'from' => 'fetch_emails', 'path' => 'emails' } }
      step_action = create(:orchestration_step_action, input_mapping: mapping)
      expect(step_action.reload.input_mapping).to eq(mapping)
    end

    it 'is nullable' do
      step_action = build(:orchestration_step_action, input_mapping: nil)
      expect(step_action).to be_valid
    end
  end
end
