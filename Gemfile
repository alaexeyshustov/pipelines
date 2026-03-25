source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "sqlite3", ">= 2.1"
gem "sqlite-vec"

# LLM
gem "ruby_llm", github: "crmne/ruby_llm", branch: "main"

# Email providers
gem "google-apis-gmail_v1"
gem "googleauth"
gem "pstore"
gem "net-imap", "~> 0.4"
gem "mail", "~> 2.8"

# Web server (require: false prevents the railtie from loading — Ruby 4.0 constant lookup incompatibility)
gem "falcon", require: false

# Pagination
gem "pagy"

# Pipeline
gem "async"
gem "async-job-adapter-active_job"
gem "dotenv-rails"
gem "dry-cli"

gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "ruby-lsp"
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false
  gem "rubycritic", require: false
  gem "brakeman", require: false
  gem "simplecov", require: false
  gem "pry"
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "vcr"
  gem "webmock"
end

group :test do
end
