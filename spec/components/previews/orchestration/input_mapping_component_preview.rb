# frozen_string_literal: true

module Orchestration
  class InputMappingComponentPreview < ViewComponent::Preview
    def default
      pipeline    = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      step        = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify", position: 1, enabled: true)
      step_action = Orchestration::StepAction.new(id: 1, step: step, position: 1, output_key: "classification", input_mapping: {})

      render(Orchestration::InputMappingComponent.new(
        step_action:      step_action,
        pipeline:         pipeline,
        step:             step,
        upstream_schemas: { "_initial" => nil }
      ))
    end

    def with_existing_mapping
      pipeline    = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      step        = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify", position: 1, enabled: true)
      mapping     = { "email_body" => { "from" => "_initial", "path" => "body" } }
      step_action = Orchestration::StepAction.new(id: 1, step: step, position: 1, output_key: "classification", input_mapping: mapping)
      schema      = { "properties" => { "subject" => {}, "body" => {}, "from" => {} } }

      render(Orchestration::InputMappingComponent.new(
        step_action:      step_action,
        pipeline:         pipeline,
        step:             step,
        upstream_schemas: { "_initial" => schema }
      ))
    end
  end
end
