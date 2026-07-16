
module Orchestration
  class InputMappingUpdater
    Result = Data.define(:saved, :errors, :warnings)

    def initialize(step_action:, input_mapping:, pipeline_validator: PipelineValidator)
      @step_action        = step_action
      @pipeline           = step_action.step.pipeline
      @input_mapping      = input_mapping
      @pipeline_validator = pipeline_validator
    end

    def update
      errors, warnings, saved = run_validation_transaction
      Result.new(saved: saved, errors: errors, warnings: warnings)
    end

    private

    def run_validation_transaction
      errors   = [] # : Array[PipelineValidator::Issue]
      warnings = [] # : Array[PipelineValidator::Issue]
      saved    = false

      ActiveRecord::Base.transaction do
        @step_action.update!(input_mapping: @input_mapping)
        errors, warnings = fetch_step_validation_results
        errors.any? ? raise(ActiveRecord::Rollback) : saved = true
      end

      [ errors, warnings, saved ]
    end

    def fetch_step_validation_results
      step_result = @pipeline_validator.new(@pipeline).validate.find { |r| r.step_action_id == @step_action.id }
      [ step_result&.errors || [], step_result&.warnings || [] ]
    end
  end
end
