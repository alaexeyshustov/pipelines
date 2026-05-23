module Orchestration
  class UpstreamSchemaIndex
    def self.build(pipeline)
      build_from_steps(pipeline, pipeline.steps.includes(step_actions: { action: :agent }))
    end

    def self.build_from_steps(pipeline, steps)
      accumulator = { "_initial" => pipeline.initial_input_schema }
      index = {} # : Hash[Integer, Hash[String, untyped]]

      steps.each do |step|
        step.step_actions.sort_by(&:position).each do |sa|
          index[sa.id] = accumulator.dup
          accumulator[sa.output_key] = sa.action.agent&.output_schema
        end
      end

      new(index)
    end

    def initialize(index)
      @index = index
    end

    def schemas_before(step_action)
      not_found = {} # : Hash[String, untyped]
      @index.fetch(step_action.id, not_found)
    end
  end
end
