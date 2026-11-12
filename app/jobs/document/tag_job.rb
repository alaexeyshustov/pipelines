# Tags one Document and stamps +tagged_at+ (like Email::ProcessJob does for emails, minus the later stages, which
# the producers queue themselves). +tagged_at+ is set only after the classifier succeeded, so a Document whose tagging
# failed stays NULL and is re-queued by a scheduled step: EmailsSync for email attachments, Document::SyncDriveJob for
# Drive files (both look at +Document.awaiting_tagging+ after REQUEUE_AFTER).
#
# Returns early, with no LLM call, for a Document that is already tagged, so duplicates queued by a slow queue are
# no-ops. RubyLLM already retries HTTP-level failures, so a RubyLLM::Error reaching this job is final for this run
# (logged, tagged_at stays nil); raw transport errors get one outer retry.
class Document::TagJob < ApplicationJob
  queue_as :default

  # How long a Document may stay untagged before the scheduled steps queue its tagging again.
  REQUEUE_AFTER = 1.hour
  TRANSPORT_ERRORS = Email::ProcessJob::TRANSPORT_ERRORS

  discard_on ActiveRecord::RecordNotFound
  retry_on(*TRANSPORT_ERRORS, wait: 5.seconds, attempts: 2) do |job, error|
    Rails.logger.error("[Document::TagJob] document #{job.arguments.first} transport error after retries: #{error.message}")
  end

  def perform(document_id)
    document = Document.find(document_id)
    return if document.tagged_at

    Tags::Classifier.call(document)
    document.update!(tagged_at: Time.current)
  rescue RubyLLM::Error => error
    Rails.logger.error("[Document::TagJob] tagging document #{document_id} failed: #{error.message}")
  end
end
