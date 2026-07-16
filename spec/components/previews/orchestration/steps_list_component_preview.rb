
module Orchestration
  class StepsListComponentPreview < ViewComponent::Preview
    def default
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline", initial_input_schema: {})
      steps    = []
      actions  = Orchestration::Action.none

      render(Orchestration::StepsListComponent.new(
        pipeline: pipeline,
        steps:    steps,
        actions:  actions
      ))
    end
  end
end
