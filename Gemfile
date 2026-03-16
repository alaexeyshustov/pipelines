source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "sqlite3", ">= 2.1"
gem "sqlite-vec"

# LLM
gem "ruby_llm", github: "crmne/ruby_llm", branch: "main"

# Email providers
gem "google-apis-gmail_v1"
gem "googleauth"
gem "net-imap", "~> 0.4"
gem "mail", "~> 2.8"

# Pipeline
gem "async"
gem "dotenv-rails"
gem "dry-cli"

gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "ruby-lsp"
  gem "pry"
end
