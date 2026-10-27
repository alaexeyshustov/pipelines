RubyLLM.configure do |config|
  config.openai_api_key   = ENV.fetch("OPENAI_API_KEY", "")
  config.mistral_api_key  = ENV.fetch("MISTRAL_API_KEY", "")
  config.gemini_api_key   = ENV.fetch("GEMINI_API_KEY", "")
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "")
  # RubyLLM 2 defaults OpenAI to the Responses API; keep Chat Completions until
  # the request formats (and recorded cassettes) are migrated.
  config.openai_protocol = :chat_completions
end
