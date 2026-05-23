# frozen_string_literal: true

module Orchestration
  class StepsListComponent < ViewComponent::Base
    def initialize(pipeline:, steps:, actions:, index:)
      @pipeline = pipeline
      @steps    = steps
      @actions  = actions
      @index    = index
      @upstream_schemas_per_step  = derive_upstream_schemas_per_step
      @validator_results_per_step = compute_validator_results_per_step
    end

    private

    def derive_upstream_schemas_per_step
      last_schemas = { "_initial" => @pipeline.initial_input_schema }
      @steps.each_with_object({}) do |step, result|
        first_action = step.step_actions.min_by(&:position)
        last_schemas = @index.schemas_before(first_action) if first_action
        result[step.id] = last_schemas
      end
    end

    def compute_validator_results_per_step
      all_results = @pipeline.validate_steps(index: @index)
      step_action_id_to_step_id = @steps.each_with_object({}) do |step, map|
        step.step_actions.each { |sa| map[sa.id] = step.id }
      end
      all_results.each_with_object(Hash.new { |h, k| h[k] = [] }) do |result, map|
        step_id = step_action_id_to_step_id[result.step_action_id]
        map[step_id] << result if step_id
      end
    end
  end
end
