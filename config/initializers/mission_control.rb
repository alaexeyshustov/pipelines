# Force solid_queue as the Mission Control adapter regardless of the per-environment
# ActiveJob adapter. Without this, Mission Control's before_initialize picks up :test
# in the test env and never prepends SolidQueueExt to the adapter.
MissionControl::Jobs.adapters = [ :solid_queue ]
ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt

# Dashboard is intentionally open in development/test (personal app, no staging).
# Production uses JOBS_DASHBOARD_USER + JOBS_DASHBOARD_PASSWORD; while either is
# unset the dashboard answers 401, so boot (and assets:precompile) never needs them.
MissionControl::Jobs.http_basic_auth_enabled = Rails.env.production?

if Rails.env.production?
  MissionControl::Jobs.http_basic_auth_user = ENV["JOBS_DASHBOARD_USER"]
  MissionControl::Jobs.http_basic_auth_password = ENV["JOBS_DASHBOARD_PASSWORD"]
end
