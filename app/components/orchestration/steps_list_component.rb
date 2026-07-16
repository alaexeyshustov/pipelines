
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
      collector =  Hash.new # : Hash[Integer, json_object]
      @steps.each_with_object(collector) do |step, result|
        result[step.id] = seen.dup
        step.step_actions.sort_by(&:position).each do |sa|
          seen[sa.output_key] = sa.action.agent&.output_schema
        end
      end
    end

    def compute_validator_results_per_step
      all_results    = @pipeline.validate_steps
      sa_to_step_map = build_step_action_to_step_map
      group_results_by_step(all_results, sa_to_step_map)
    end

    def build_step_action_to_step_map
      collector = Hash.new # : Hash[Integer, Integer]
      @steps.each_with_object(collector) do |step, map|
        step.step_actions.each { |sa| map[sa.id] = step.id }
      end
    end

    def group_results_by_step(all_results, sa_to_step_map)
      collector = Hash.new { |h, k| h[k] = [] } # : Hash[Integer, Array[Orchestration::ValidatorResult]]
      all_results.each_with_object(collector) do |result, map|
        step_id = sa_to_step_map[result.step_action_id]
        map[step_id] << result if step_id
      end
    end
  end
end
