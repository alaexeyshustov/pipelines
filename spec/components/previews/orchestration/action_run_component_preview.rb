
module Orchestration
  class ActionRunComponentPreview < ViewComponent::Preview
    def default
      pipeline    = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      step        = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify", position: 1, enabled: true)
      action      = Orchestration::Action.new(id: 1, name: "ClassifyEmail")
      step_action = Orchestration::StepAction.new(id: 1, step: step, action: action, position: 1, output_key: "result", input_mapping: {})
      pipeline_run = Orchestration::PipelineRun.new(id: 1, pipeline: pipeline, status: "completed")
      action_run = Orchestration::ActionRun.new(
        id: 1, step_action: step_action, pipeline_run: pipeline_run,
        status: "completed",
        input: { "subject" => "Job Offer" },
        output: { "classification" => "offer" },
        started_at: 10.seconds.ago,
        finished_at: 5.seconds.ago,
        error_details: nil
      )
      render(Orchestration::ActionRunComponent.new(action_run: action_run))
    end

    def failed
      pipeline    = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      step        = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify", position: 1, enabled: true)
      action      = Orchestration::Action.new(id: 1, name: "ClassifyEmail")
      step_action = Orchestration::StepAction.new(id: 1, step: step, action: action, position: 1, output_key: "result", input_mapping: {})
      pipeline_run = Orchestration::PipelineRun.new(id: 1, pipeline: pipeline, status: "failed")
      action_run = Orchestration::ActionRun.new(
        id: 1, step_action: step_action, pipeline_run: pipeline_run,
        status: "failed",
        input: { "subject" => "Job Offer" },
        output: nil,
        started_at: 10.seconds.ago,
        finished_at: 8.seconds.ago,
        error_details: { "message" => "Timeout", "code" => "TIMEOUT" }
      )
      render(Orchestration::ActionRunComponent.new(action_run: action_run))
    end
  end
end
