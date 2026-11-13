target :app do
  signature "sig"

  check "app/services"
  check "app/tools"
  check "lib"
  check "app/jobs/email/sync_inbox_job.rb"
  check "app/jobs/email/sync_inbox_job"
  ignore "lib/view_primitives"

  library "pathname"
  library "json"
  library "csv"
  library "date"
  library "time"
  library "uri"
  library "monitor"
  library "singleton"
  library "socket"
  library "fileutils"
end
