class ApplicationJob < ActiveJob::Base
  # Errors of the connection itself (not of the provider's answer): jobs that call an LLM retry them once.
  TRANSPORT_ERRORS = [ RubyLLM::ConnectionError, Net::OpenTimeout, Net::ReadTimeout ].freeze
end
