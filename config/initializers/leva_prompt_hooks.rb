Rails.application.config.after_initialize do
  unless Leva::Prompt.ancestors.include?(Evaluation::AutoEvalTriggerable)
    Leva::Prompt.include(Evaluation::AutoEvalTriggerable)
  end
end
