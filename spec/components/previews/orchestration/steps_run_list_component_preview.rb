
module Orchestration
  class StepsRunListComponentPreview < ViewComponent::Preview
    def default
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      run      = Orchestration::PipelineRun.new(id: 1, pipeline: pipeline, initial_input: nil)

      render(Orchestration::StepsRunListComponent.new(
        pipeline:            pipeline,
        run:                 run,
        action_runs_by_step: {}
      ))
    end
  end
end
