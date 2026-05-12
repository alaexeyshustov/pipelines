# frozen_string_literal: true

# Extend Leva's built-in job classes with retry behaviour for transient LLM
# errors (e.g. brief API outages or unknown HTTP status codes returned by
# Mistral/OpenAI). The job is safe to retry because RunnerResult is only
# persisted *after* a successful execute call, so a failed attempt leaves no
# partial state.
Rails.application.config.after_initialize do
  Leva::RunEvalJob.retry_on RubyLLM::Error,
                             wait:     :polynomially_longer,
                             attempts: 3
end
