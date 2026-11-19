module Evaluation
  # The version live for a prompt's agent, or the agent's own prompt when none is active, for diffing against.
  module ActivePromptLookup
    extend ActiveSupport::Concern

    private

    def active_prompt_for(prompt)
      return unless prompt

      Prompt.active_for_agent(prompt.name) ||
        AgentDefaultPrompt.new(system_prompt: Prompt.agent_default_for(prompt.name), user_prompt: "")
    end
  end
end
