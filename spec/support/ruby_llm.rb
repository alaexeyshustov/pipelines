# RubyLLM 2.x refuses to build a provider without credentials, so give every
# provider a placeholder key. Requests are stubbed by WebMock/VCR.
RubyLLM.configure do |config|
  config.openai_api_key    = 'test-key' if config.openai_api_key.blank?
  config.mistral_api_key   = 'test-key' if config.mistral_api_key.blank?
  config.gemini_api_key    = 'test-key' if config.gemini_api_key.blank?
  config.anthropic_api_key = 'test-key' if config.anthropic_api_key.blank?
end
