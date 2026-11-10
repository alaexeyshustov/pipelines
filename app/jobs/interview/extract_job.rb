# Interview stage of the per-email processing chain (ADR 0013): upserts the Interview a job_application email belongs
# to (Interviews::EmailExtractor). Enqueued by Email::ProcessJob. Re-runs are idempotent.
#
# Email::ProcessJob has already stamped +tagged_at+ when this is queued, and nothing queues it again, so a provider
# error (RubyLLM::Error, after RubyLLM's own HTTP retries) is retried here with a growing wait before it is logged
# as final; raw transport errors get one outer retry.
class Interview::ExtractJob < ApplicationJob
  queue_as :default

  TRANSPORT_ERRORS = Email::ProcessJob::TRANSPORT_ERRORS

  retry_on(*TRANSPORT_ERRORS, wait: 5.seconds, attempts: 2) do |job, error|
    Rails.logger.error("[Interview::ExtractJob] email #{job.arguments.first} transport error after retries: #{error.message}")
  end

  retry_on RubyLLM::Error, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.error("[Interview::ExtractJob] extracting email #{job.arguments.first} failed after retries: #{error.message}")
  end

  def perform(email_id)
    Interviews::EmailExtractor.call(Email.find(email_id))
  end
end
