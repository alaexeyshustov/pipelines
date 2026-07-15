module Orchestration
  # Instance-based (responds to #call, not .call) because the PromptResolver port
  # is instantiated per run to carry run-scoped cache state; a stateless
  # .call-singleton could not hold that state. The default resolves no prompt.
  class NullPromptResolver
    def call(_agent_class) = nil
  end
end
