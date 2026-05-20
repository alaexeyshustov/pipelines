# frozen_string_literal: true

module Orchestration
  class InputMappingForm
    include ActiveModel::Model

    attr_reader :result

    validate :new_key_format_valid

    def initialize(step_action:, input_mapping:, new_key: nil, new_from: nil, new_path: nil)
      @step_action = step_action
      raw = input_mapping || {}
      @base_mapping = (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h).deep_stringify_keys
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
      mapping = @base_mapping.dup
      if @new_key && @new_from
        mapping[@new_key] = { "from" => @new_from, "path" => @new_path }.compact
      end
      mapping
    end
  end
end
