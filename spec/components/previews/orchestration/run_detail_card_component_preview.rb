
module Orchestration
  class RunDetailCardComponentPreview < ViewComponent::Preview
    def completed
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      run = Orchestration::PipelineRun.new(
        id: 1, pipeline: pipeline, status: "completed",
        started_at: 2.minutes.ago, finished_at: 1.minute.ago
      )
      render(Orchestration::RunDetailCardComponent.new(run: run))
    end

    def running
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      run = Orchestration::PipelineRun.new(
        id: 2, pipeline: pipeline, status: "running",
        started_at: 30.seconds.ago, finished_at: nil
      )
      render(Orchestration::RunDetailCardComponent.new(run: run))
    end

    def not_started
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      run = Orchestration::PipelineRun.new(
        id: 3, pipeline: pipeline, status: "pending",
        started_at: nil, finished_at: nil
      )
      render(Orchestration::RunDetailCardComponent.new(run: run))
    end
  end
end
