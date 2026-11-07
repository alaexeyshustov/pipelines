module Emails
  # A provider's credentials are missing (Gmail credentials file, Yahoo username/password), so it cannot be used at
  # all. Callers such as the scheduled inbox sync treat it as "skipped", not as a failure.
  class NotConfigured < StandardError; end
end
