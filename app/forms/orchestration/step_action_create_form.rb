# frozen_string_literal: true

module Orchestration
  class StepActionCreateForm < ::BaseForm
    attr_reader :step_action

    validate :action_exists
    validate :params_json_valid

    def initialize(step:, action_id:, params_json: nil)
      @step = step
      @action_id = action_id.to_i
      raw = params_json.presence
      if raw
        begin
          @parsed_params = JSON.parse(raw)
        rescue JSON::ParserError
          @params_parse_error = true
        end
      end
    end

    def save
      return false unless valid?

      next_position = (@step.step_actions.maximum(:position) || 0) + 1
      key = Orchestration::OutputKeyDeriver.call(action_name: action.name, step: @step)
      @step_action = @step.step_actions.build(
        action_id: action.id,
        params: @parsed_params,
        position: next_position,
        output_key: key
      )

      begin
        saved = @step_action.save
      rescue ActiveRecord::RecordNotUnique
        @step_action.output_key = "#{key}_#{SecureRandom.hex(3)}"
        saved = @step_action.save
      end

      saved
    end

    private

    def action_exists
      errors.add(:base, "Invalid action.") unless action
    end

    def params_json_valid
      errors.add(:base, "Params must be valid JSON.") if @params_parse_error
    end

    def action
      return @action if defined?(@action)

      @action = Orchestration::Action.find_by(id: @action_id)
    end
  end
end
