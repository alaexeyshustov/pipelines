# Per-email processing chain after ingest (ADR 0013): tag the email, stamp +tagged_at+, then hand it to the later
# stages (attachments, and the Interview upsert for job_application emails), each its own job so it retries on its
# own. Attachments are extracted when the email has any tagging (manual ones count). +tagged_at+ is set only after the classifier succeeded, so an email whose tagging failed stays
# NULL and EmailsSync re-enqueues it on a later run.
#
# Retries mirror Evaluation::SampleJob: RubyLLM already retries HTTP-level failures, so a RubyLLM::Error reaching
# this job is final for this run (logged, tagged_at stays nil); raw transport errors get one outer retry.
class Email::ProcessJob < ApplicationJob
  queue_as :default

  TRANSPORT_ERRORS = [ Faraday::ConnectionFailed, Faraday::TimeoutError, Net::OpenTimeout, Net::ReadTimeout ].freeze

  retry_on(*TRANSPORT_ERRORS, wait: 5.seconds, attempts: 2) do |job, error|
    Rails.logger.error("[Email::ProcessJob] email #{job.arguments.first} transport error after retries: #{error.message}")
  end

  def perform(email_id)
    email = Email.find(email_id)
    Tags::Classifier.call(email)
    email.update!(tagged_at: Time.current)
    enqueue_later_stages(email)
  rescue RubyLLM::Error => error
    Rails.logger.error("[Email::ProcessJob] tagging email #{email_id} failed: #{error.message}")
  end

  private

  def enqueue_later_stages(email)
    Document::ExtractEmailAttachmentsJob.perform_later(email.id) if email.taggings.exists?
    enqueue_interview_extraction(email)
  end

  # The Interview stage (#239, #228) only concerns job application emails, manual taggings included.
  def enqueue_interview_extraction(email)
    Interview::ExtractJob.perform_later(email.id) if email.tags.find_by(name: Interviews::EmailExtractor::TAG)
  end
end
