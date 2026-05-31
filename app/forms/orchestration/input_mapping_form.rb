# frozen_string_literal: true

module Orchestration
  class InputMappingForm < ::BaseForm
    attr_reader :result

    validate :new_key_format_valid

    def initialize(step_action:, input_mapping:, new_key: nil, new_from: nil, new_path: nil)
      @step_action = step_action
      @base_mapping = (input_mapping&.to_unsafe_h || {}).deep_stringify_keys
      @new_key = new_key.presence
      @new_from = new_from.presence
      @new_path = new_path.presence
    end

    def save
      return false unless valid?

      @result = Orchestration::InputMappingUpdater.call(
        step_action: @step_action,
        input_mapping: build_mapping
      )
      @result.saved
    end

    private

    def new_key_format_valid
      return unless @new_key
      return if @new_key.match?(Orchestration::StepAction::OUTPUT_KEY_FORMAT)

      errors.add(:base, "Key #{@new_key.inspect} is invalid: must only contain lowercase letters, digits, and underscores, and start with a letter.")
    end

    def build_mapping
      mapping = @base_mapping
        .reject { |_k, spec| spec.is_a?(Hash) && spec["_destroy"] == "1" }
        .transform_values do |spec|
          next spec unless spec.is_a?(Hash)
          spec.except("_destroy").reject { |k, v| k == "path" && v.blank? }
        end
      if @new_key && @new_from
        mapping[@new_key] = { "from" => @new_from, "path" => @new_path }.compact
      end
      mapping
    end
  end
end
