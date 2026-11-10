require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join('spec/cassettes')
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive credentials from cassettes
  config.filter_sensitive_data('<GMAIL_CLIENT_ID>')     { ENV['GMAIL_CLIENT_ID'] }
  config.filter_sensitive_data('<GMAIL_CLIENT_SECRET>') { ENV['GMAIL_CLIENT_SECRET'] }
  config.filter_sensitive_data('<GMAIL_ACCESS_TOKEN>')  { ENV['GMAIL_ACCESS_TOKEN'] }
  config.filter_sensitive_data('<MISTRAL_API_KEY>')     { ENV['MISTRAL_API_KEY'] }
  config.filter_sensitive_data('<GITHUB_TOKEN>')        { ENV['GITHUB_TOKEN'] }
  config.filter_sensitive_data('<MISTRAL_BEARER>') do |interaction|
    auth = interaction.request.headers['Authorization']&.first
    auth&.sub(/^Bearer\s+/, '')
  end
  config.filter_sensitive_data('<OPENAI_API_KEY>')     { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<GEMINI_API_KEY>')      { ENV['GEMINI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>')   { ENV['ANTHROPIC_API_KEY'] }

  config.ignore_localhost = true

  # LLM_TEST_BACKEND=ollama (spec/support/llm_test_backend.rb): Ollama calls are live, and a hosted LLM request
  # must fail rather than replay or record a cassette.
  if LlmTestBackend.ollama?
    config.ignore_hosts LlmTestBackend.host
    config.before_http_request(->(request) { LlmTestBackend.hosted_llm_request?(request.uri) }) do |request|
      raise "LLM_TEST_BACKEND=ollama: hosted LLM request to #{request.uri}; route the model to LlmTestBackend.model"
    end
  end

  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: [ :method, :uri ]
  }
end
