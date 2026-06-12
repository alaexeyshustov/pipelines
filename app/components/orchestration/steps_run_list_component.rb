# frozen_string_literal: true

module Orchestration
  class StepsRunListComponent < ViewComponent::Base
    include SteepHacks

    def initialize(pipeline:, run:, action_runs_by_step:)
      @pipeline            = pipeline
      @run                 = run
      @action_runs_by_step = action_runs_by_step
      @steps_with_action_runs = compute_steps_with_action_runs
    end

    private

    def compute_steps_with_action_runs
      accumulated_outputs = { "_initial" => @run.initial_input }.compact

      @pipeline.steps.map do |step|
        available_outputs = accumulated_outputs.dup
        action_runs       = @action_runs_by_step.fetch(step.id, [])
        action_runs.each { |ar| accumulated_outputs[ar.step_action.output_key] = ar.output || empty_object }
        {
          step:           step,
          action_runs:    action_runs,
          derived_status: Orchestration::Step.derive_status(action_runs),
          available_outputs: available_outputs
        }
      end
    end
  end
end
