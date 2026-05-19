MissionControl::Jobs.adapters = [ :solid_queue ]
ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt

MissionControl::Jobs.http_basic_auth_enabled = Rails.env.production?

if Rails.env.production?
  MissionControl::Jobs.username = ENV.fetch("JOBS_DASHBOARD_USER", "admin")
  MissionControl::Jobs.password = ENV.fetch("JOBS_DASHBOARD_PASSWORD") do
    raise "JOBS_DASHBOARD_PASSWORD env var is required in production"
  end
end
