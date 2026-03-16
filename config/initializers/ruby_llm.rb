RubyLLM.configure do |config|
  config.openai_api_key   = ENV.fetch("OPENAI_API_KEY", "")
  config.mistral_api_key  = ENV.fetch("MISTRAL_API_KEY", "")
  config.gemini_api_key   = ENV.fetch("GEMINI_API_KEY", "")
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "")
end
