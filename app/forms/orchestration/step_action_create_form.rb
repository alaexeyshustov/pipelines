
module Orchestration
  class StepActionCreateForm < ::BaseForm
    attr_reader :step_action

    validate :action_exists

    def initialize(step:, action_id:)
      @step = step
      @action_id = action_id.to_i
    end

    def save
      return false unless valid?

      key          = Orchestration::OutputKeyDeriver.new(action_name: action.name, step: @step).derive
      @step_action = build_step_action(key)
      save_with_unique_key_retry(key)
    end

    private

    def build_step_action(key)
      next_position = (@step.step_actions.maximum(:position) || 0) + 1
      @step.step_actions.build(action_id: action.id, position: next_position, output_key: key)
    end

    def save_with_unique_key_retry(key)
      @step_action.save
    rescue ActiveRecord::RecordNotUnique
      @step_action.output_key = "#{key}_#{SecureRandom.hex(3)}"
      @step_action.save
    end

    def action_exists
      errors.add(:base, "Invalid action.") unless action
    end

    def action
      return @action if defined?(@action)

      @action = Orchestration::Action.find_by(id: @action_id)
    end
  end
end
