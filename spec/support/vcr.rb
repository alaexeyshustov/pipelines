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

  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: [ :method, :uri ]
  }
end
