RubyLLM.configure do |config|
  config.openai_api_key   = ENV.fetch("OPENAI_API_KEY", "")
  config.mistral_api_key  = ENV.fetch("MISTRAL_API_KEY", "")
  config.gemini_api_key   = ENV.fetch("GEMINI_API_KEY", "")
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "")
  # Local models (Ollama's OpenAI-compatible endpoint): embeddings (ADR 0014) and chat models addressed as
  # "ollama/<model>" (GH #208, see LlmModels). Always configured, since embeddings need it; the key is for proxied setups.
  config.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")
  config.ollama_api_key  = ENV["OLLAMA_API_KEY"] if ENV["OLLAMA_API_KEY"].present?
  # RubyLLM 2 defaults OpenAI to the Responses API; keep Chat Completions until
  # the request formats (and recorded cassettes) are migrated.
  config.openai_protocol = :chat_completions
end
