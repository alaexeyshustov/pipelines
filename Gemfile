source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "sqlite3", ">= 2.1"
gem "sqlite-vec"

gem "aasm", "~> 5.5"
gem "view_component", "~> 4.6"

# Evaluation framework
gem "liquid"

# LLM
gem "ruby_llm", github: "crmne/ruby_llm", branch: "main"
gem "ruby_llm-schema"
gem "ruby_llm-monitoring"

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
gem "diffy"
gem "csv"

# Assets
gem "propshaft"
gem "jsbundling-rails"
gem "tailwindcss-rails"
gem "turbo-rails"
gem "stimulus-rails"

# Pipeline
gem "async"
gem "fugit"
gem "solid_queue", github: "crmne/solid_queue", branch: "async-worker-execution-mode"
gem "mission_control-jobs"
gem "dotenv-rails"
gem "dry-cli"

gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "simplecov", require: false
  gem "reline"
  gem "pry"
  gem "pry-nav"
end

group :development do
  gem "brakeman", require: false
  gem "mutant", require: false
  gem "mutant-rspec", require: false
  # parser 3.x does not yet support Ruby 4.0 — emits a parser/current warning on every mutant run.
  # Upgrade to 4.x once upstream releases Ruby 4.0 support:
  # https://github.com/whitequark/parser#compatibility-with-ruby-mri
  gem "parser", "~> 3.3", require: false
  gem "rubycritic", require: false
  gem "rubocop", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false
  gem "rubocop-on-rbs", require: false
  gem "steep", require: false
  gem "rbs-sentinel", require: false
  gem "rbs_rails", "~> 0.13.0"
  gem "ruby-lsp"
end

group :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "vcr"
  gem "webmock"
  gem "capybara", "~> 3.40"
end
