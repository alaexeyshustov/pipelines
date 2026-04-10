# frozen_string_literal: true

module Orchestration
  class StepComponentPreview < ViewComponent::Preview
    def default
      pipeline = Orchestration::Pipeline.first || Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      actions  = Orchestration::Action.all
      step     = Orchestration::Step.new(id: 1, pipeline: pipeline, name: "Classify Emails", position: 1, enabled: true)
      iteration = OpenStruct.new(first?: true, last?: false)

      render(Orchestration::StepComponent.new(
        step: step, step_counter: 1, step_iteration: iteration,
        pipeline: pipeline, actions: actions
      ))
    end

    def disabled
      pipeline  = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      actions   = Orchestration::Action.all
      step      = Orchestration::Step.new(id: 2, pipeline: pipeline, name: "Label Emails", position: 2, enabled: false)
      iteration = OpenStruct.new(first?: false, last?: false)

      render(Orchestration::StepComponent.new(
        step: step, step_counter: 2, step_iteration: iteration,
        pipeline: pipeline, actions: actions
      ))
    end

    def last_step
      pipeline  = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      actions   = Orchestration::Action.all
      step      = Orchestration::Step.new(id: 3, pipeline: pipeline, name: "Final Step", position: 3, enabled: true)
      iteration = OpenStruct.new(first?: false, last?: true)

      render(Orchestration::StepComponent.new(
        step: step, step_counter: 3, step_iteration: iteration,
        pipeline: pipeline, actions: actions
      ))
    end
  end
end
