# Force solid_queue as the Mission Control adapter regardless of the per-environment
# ActiveJob adapter. Without this, Mission Control's before_initialize picks up :test
# in the test env and never prepends SolidQueueExt to the adapter.
MissionControl::Jobs.adapters = [ :solid_queue ]
ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt

# The dashboard inherits from ::ApplicationController, so the app's login gates it (GH #255).
MissionControl::Jobs.http_basic_auth_enabled = false
