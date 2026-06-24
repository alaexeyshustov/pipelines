# frozen_string_literal: true

module Evaluation
  class PromptDiffComponentPreview < ViewComponent::Preview
    def default
      prompt_a = Evaluation::Prompt.new(
        id: 1, version: 1,
        system_prompt: "You are a helpful classifier.",
        user_prompt: "Classify the following email: {{input}}"
      )
      prompt_b = Evaluation::Prompt.new(
        id: 2, version: 2,
        system_prompt: "You are a precise and helpful classifier.",
        user_prompt: "Carefully classify the following email: {{input}}\nProvide a confidence score."
      )
      render(Evaluation::PromptDiffComponent.new(prompt_a: prompt_a, prompt_b: prompt_b))
    end
  end
end
