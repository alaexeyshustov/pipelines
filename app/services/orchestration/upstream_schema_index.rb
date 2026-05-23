module Orchestration
  class UpstreamSchemaIndex
    def self.build(pipeline)
      accumulator = { "_initial" => pipeline.initial_input_schema }
      index = {}

      pipeline.steps.includes(step_actions: { action: :agent }).each do |step|
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
      @index.fetch(step_action.id, { "_initial" => nil })
    end
  end
end
