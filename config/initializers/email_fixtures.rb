# EMAIL_FIXTURES=<path to a JSON mailbox> serves Gmail and Yahoo from that file instead of the real mailboxes
# (Emails::Adapters::FixtureAdapter); the Playwright e2e run sets it. Never in production.
if (path = ENV["EMAIL_FIXTURES"].presence) && !Rails.env.production?
  Rails.application.config.after_initialize { Emails.use_fixtures(path) }
end
