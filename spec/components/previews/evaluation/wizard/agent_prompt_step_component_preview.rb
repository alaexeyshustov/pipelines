# frozen_string_literal: true

module Evaluation
  module Wizard
    class AgentPromptStepComponentPreview < ViewComponent::Preview
      def default
        prompt = Evaluation::Prompt.new(id: 1, name: "ClassifyAgent", version: 2,
                                        system_prompt: "You are a classifier.",
                                        user_prompt: "Classify: {{input}}")
        form = OpenStruct.new(
          agent_names: %w[ClassifyAgent SummaryAgent],
          prompts: [ prompt ],
          agent_name: "ClassifyAgent",
          prompt_id: 1,
          experiment_name: "My Experiment",
          available_models: { "anthropic" => %w[claude-sonnet-4-6 claude-haiku-4-5] },
          sample_model: "claude-sonnet-4-6",
          evaluation_model: "claude-sonnet-4-6"
        )
        render(Evaluation::Wizard::AgentPromptStepComponent.new(form: form))
      end
    end
  end
end
