# frozen_string_literal: true

module Orchestration
  class StepsListComponent < ViewComponent::Base
    def initialize(pipeline:, steps:, actions:)
      @pipeline = pipeline
      @steps    = steps
      @actions  = actions
      @upstream_schemas_per_step  = compute_upstream_schemas_per_step
      @validator_results_per_step = compute_validator_results_per_step
    end

    private

    def compute_upstream_schemas_per_step
      seen = { "_initial" => @pipeline.initial_input_schema }
      @steps.each_with_object({}) do |step, result|
        result[step.id] = seen.dup
        step.step_actions.sort_by(&:position).each do |sa|
          seen[sa.output_key] = sa.action.output_schema
        end
      end
    end

    def compute_validator_results_per_step
      all_results = Pipeline::Validator.call(@pipeline)
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
