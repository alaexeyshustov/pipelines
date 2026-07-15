module Orchestration
  # Holds the prompt-resolution port as a class/factory (not an instance): each
  # PipelineRunner calls `.new` on it to obtain a per-run resolver that can carry
  # run-scoped cache state. Defaults to the no-op NullPromptResolver so
  # Orchestration has no load-time dependency on Evaluation; the Evaluation-owned
  # adapter is wired in at boot (config/initializers/orchestration.rb).
  mattr_accessor :prompt_resolver
  self.prompt_resolver = NullPromptResolver
end
