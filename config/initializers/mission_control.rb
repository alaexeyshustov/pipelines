# Force solid_queue as the Mission Control adapter regardless of the per-environment
# ActiveJob adapter. Without this, Mission Control's before_initialize picks up :test
# in the test env and never prepends SolidQueueExt to the adapter.
MissionControl::Jobs.adapters = [ :solid_queue ]
ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt

# Dashboard is intentionally open in development/test (personal app, no staging).
# Production requires JOBS_DASHBOARD_USER + JOBS_DASHBOARD_PASSWORD env vars.
MissionControl::Jobs.http_basic_auth_enabled = Rails.env.production?

if Rails.env.production?
  MissionControl::Jobs.username = ENV.fetch("JOBS_DASHBOARD_USER")
  MissionControl::Jobs.password = ENV.fetch("JOBS_DASHBOARD_PASSWORD")
end
