module Evaluation
  # Evaluation-owned adapter for Orchestration's PromptResolver port. Returns the
  # activated version's system prompt, or nil so the agent's own prompt applies.
  # Instantiated once per pipeline run; the instance memoizes lookups (including nil results)
  # for the lifetime of that run. Fresh instance per run means no stale cross-run
  # caching.
  class ActivePromptResolver
    def initialize
      @cache = {}
    end

    def call(agent_class)
      return @cache[agent_class] if @cache.key?(agent_class)

      @cache[agent_class] = Evaluation::Prompt.active_for_agent(agent_class)&.system_prompt
    end
  end
end
