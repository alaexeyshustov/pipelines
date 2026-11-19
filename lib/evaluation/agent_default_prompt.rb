module Evaluation
  # Stand-in for "no version is active": the agent's own prompt, shaped like a Prompt for diffing.
  class AgentDefaultPrompt < Data.define(:system_prompt, :user_prompt)
    def label = "Agent default"
  end
end
