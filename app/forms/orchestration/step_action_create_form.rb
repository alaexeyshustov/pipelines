# frozen_string_literal: true

module Orchestration
  class StepActionCreateForm
    include ActiveModel::Model

    attr_reader :step_action

    validate :action_exists
    validate :params_json_valid

    def initialize(step:, action_id:, params_json: nil)
      @step = step
      @action_id = action_id.to_i
      @params_json = params_json.presence
    end

    def save
      return false unless valid?

      next_position = (@step.step_actions.maximum(:position) || 0) + 1
      key = Orchestration::OutputKeyDeriver.call(action_name: action.name, step: @step)
      @step_action = @step.step_actions.build(
        action_id: action.id,
        params: parsed_params,
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
      return if @params_json.nil?

      JSON.parse(@params_json)
    rescue JSON::ParserError
      errors.add(:base, "Params must be valid JSON.")
    end

    def action
      @action ||= Orchestration::Action.find_by(id: @action_id)
    end

    def parsed_params
      return nil if @params_json.nil?

      JSON.parse(@params_json)
    end
  end
end
