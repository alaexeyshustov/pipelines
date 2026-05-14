# frozen_string_literal: true

module Orchestration
  class StepActionEditorComponent < ViewComponent::Base
    with_collection_parameter :step_action

    def initialize(step_action:, step_action_counter:, step_action_iteration:,
                   pipeline:, step:, upstream_schemas:, validator_results:)
      @step_action       = step_action
      @pipeline          = pipeline
      @step              = step
      @upstream_schemas  = upstream_schemas
      @validator_results = validator_results
    end

    def validation_errors
      result = @validator_results.find { |r| r.step_action_id == @step_action.id }
      result&.errors || []
    end
  end
end
