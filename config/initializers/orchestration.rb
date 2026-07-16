Rails.application.config.to_prepare do
  Orchestration.prompt_resolver = Evaluation::ActivePromptResolver
  Rails.logger.debug("[Orchestration] prompt_resolver wired to Evaluation::ActivePromptResolver")
end
