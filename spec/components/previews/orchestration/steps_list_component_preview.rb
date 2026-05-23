# frozen_string_literal: true

module Orchestration
  class StepsListComponentPreview < ViewComponent::Preview
    def default
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline", initial_input_schema: {})
      steps    = []
      actions  = Orchestration::Action.none
      index    = Orchestration::UpstreamSchemaIndex.new({})

      render(Orchestration::StepsListComponent.new(
        pipeline: pipeline,
        steps:    steps,
        actions:  actions,
        index:    index
      ))
    end
  end
end
