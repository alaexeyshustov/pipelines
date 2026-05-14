# frozen_string_literal: true

module Orchestration
  class StepActionEditorComponentPreview < ViewComponent::Preview
    def default
      pipeline    = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      step        = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify", position: 1, enabled: true)
      step_action = Orchestration::StepAction.new(id: 1, step: step, position: 1, output_key: "classification", input_mapping: {})
      iteration   = OpenStruct.new(first?: true, last?: true)

      render(Orchestration::StepActionEditorComponent.new(
        step_action:             step_action,
        step_action_counter:     1,
        step_action_iteration:   iteration,
        pipeline:                pipeline,
        step:                    step,
        upstream_schemas:        { "_initial" => nil },
        validator_results:       []
      ))
    end
  end
end
