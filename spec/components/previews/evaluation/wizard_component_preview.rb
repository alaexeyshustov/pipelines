# frozen_string_literal: true

module Evaluation
  class WizardComponentPreview < ViewComponent::Preview
    def step_one
      prompt  = Evaluation::Prompt.new(id: 1, name: "ClassifyAgent", version: 2,
                                       system_prompt: "You are a classifier.",
                                       user_prompt: "Classify: {{input}}")
      step1_form = OpenStruct.new(
        agent_names: %w[ClassifyAgent SummaryAgent],
        prompts: [ prompt ],
        agent_name: "ClassifyAgent",
        prompt_id: 1,
        experiment_name: "My Experiment",
        available_models: { "anthropic" => %w[claude-sonnet-4-6] },
        sample_model: "claude-sonnet-4-6",
        evaluation_model: "claude-sonnet-4-6"
      )
      form = OpenStruct.new(step_form: ->(_step) { step1_form })
      render(Evaluation::WizardComponent.new(current_step: 1, form: form))
    end

    def step_two
      metrics_form = OpenStruct.new(
        agent_name: "ClassifyAgent",
        metrics: [ Evaluation::Metric.new(id: 1, name: "accuracy", agent_name: "ClassifyAgent") ]
      )
      form = OpenStruct.new(step_form: ->(_step) { metrics_form })
      render(Evaluation::WizardComponent.new(current_step: 2, form: form))
    end
  end
end
