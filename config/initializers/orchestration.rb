Rails.application.config.to_prepare do
  Orchestration.prompt_resolver = Evaluation::ActivePromptResolver
  unless Orchestration.prompt_resolver == Evaluation::ActivePromptResolver
    raise "Orchestration.prompt_resolver not wired to Evaluation::ActivePromptResolver"
  end
  Rails.logger.info("[Orchestration] prompt_resolver wired to Evaluation::ActivePromptResolver")
end
