Rails.application.config.after_initialize do
  Leva::Prompt.after_create_commit do |prompt|
    Evaluation::PromptAutoEvalJob.perform_later(prompt)
  end
end
