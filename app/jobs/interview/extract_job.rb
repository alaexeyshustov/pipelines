# Interview stage of the per-email processing chain (ADR 0013): upserts the Interview a job_application email belongs
# to (Interviews::EmailExtractor). Enqueued by Email::ProcessJob. Re-runs are idempotent.
#
# Retries mirror Email::ProcessJob: RubyLLM already retries HTTP-level failures, so a RubyLLM::Error reaching this
# job is final for this run (logged, nothing written); raw transport errors get one outer retry.
class Interview::ExtractJob < ApplicationJob
  queue_as :default

  TRANSPORT_ERRORS = Email::ProcessJob::TRANSPORT_ERRORS

  retry_on(*TRANSPORT_ERRORS, wait: 5.seconds, attempts: 2) do |job, error|
    Rails.logger.error("[Interview::ExtractJob] email #{job.arguments.first} transport error after retries: #{error.message}")
  end

  def perform(email_id)
    Interviews::EmailExtractor.call(Email.find(email_id))
  rescue RubyLLM::Error => error
    Rails.logger.error("[Interview::ExtractJob] extracting email #{email_id} failed: #{error.message}")
  end
end
