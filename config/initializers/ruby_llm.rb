RubyLLM.configure do |config|
  config.openai_api_key   = ENV.fetch("OPENAI_API_KEY", "")
  config.mistral_api_key  = ENV.fetch("MISTRAL_API_KEY", "")
  config.gemini_api_key   = ENV.fetch("GEMINI_API_KEY", "")
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "")
  # Local models (Ollama), addressed as "ollama/<model>" (see LlmModels). Set only when present: RubyLLM refuses to
  # build the provider without a base URL, so an unset base keeps Ollama unconfigured. The key is for proxied setups.
  config.ollama_api_base = ENV["OLLAMA_API_BASE"] if ENV["OLLAMA_API_BASE"].present?
  config.ollama_api_key  = ENV["OLLAMA_API_KEY"] if ENV["OLLAMA_API_KEY"].present?
  # RubyLLM 2 defaults OpenAI to the Responses API; keep Chat Completions until
  # the request formats (and recorded cassettes) are migrated.
  config.openai_protocol = :chat_completions
end
