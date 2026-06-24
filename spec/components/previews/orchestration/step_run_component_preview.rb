# frozen_string_literal: true

module Orchestration
  class StepRunComponentPreview < ViewComponent::Preview
    def completed
      pipeline     = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      step         = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify", position: 1, enabled: true)
      action       = Orchestration::Action.new(id: 1, name: "ClassifyEmail")
      step_action  = Orchestration::StepAction.new(id: 1, step: step, action: action, position: 1, output_key: "result", input_mapping: {})
      pipeline_run = Orchestration::PipelineRun.new(id: 1, pipeline: pipeline, status: "completed")
      action_run   = Orchestration::ActionRun.new(
        id: 1, step_action: step_action, pipeline_run: pipeline_run,
        status: "completed",
        input: { "subject" => "Job Offer" },
        output: { "classification" => "offer" },
        started_at: 5.seconds.ago, finished_at: 3.seconds.ago,
        error_details: nil
      )
      entry = {
        step: step,
        action_runs: [ action_run ],
        derived_status: "completed",
        available_outputs: { "result" => { "classification" => "offer" } }
      }
      render(Orchestration::StepRunComponent.new(entry: entry))
    end
  end
end
