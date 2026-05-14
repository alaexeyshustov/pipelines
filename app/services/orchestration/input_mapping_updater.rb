# frozen_string_literal: true

module Orchestration
  class InputMappingUpdater
    Result = Data.define(:saved, :errors, :warnings)

    def self.call(step_action:, input_mapping:) = new(step_action: step_action, input_mapping: input_mapping).call

    def initialize(step_action:, input_mapping:)
      @step_action   = step_action
      @pipeline      = step_action.step.pipeline
      @input_mapping = input_mapping
    end

    def call
      errors   = [] # : Array[Pipeline::Validator::Issue]
      warnings = [] # : Array[Pipeline::Validator::Issue]
      saved    = false

      ActiveRecord::Base.transaction do
        @step_action.update!(input_mapping: @input_mapping)
        all_results = Pipeline::Validator.call(@pipeline)
        step_result = all_results.find { |r| r.step_action_id == @step_action.id }
        errors      = step_result&.errors   || []
        warnings    = step_result&.warnings || []

        if errors.any?
          raise ActiveRecord::Rollback
        else
          saved = true
        end
      end

      Result.new(saved: saved, errors: errors, warnings: warnings)
    end
  end
end
