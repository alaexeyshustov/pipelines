# Classifies one Document with Tags::Classify (see there for the status it leaves). Document::SyncDriveJob queues it
# for new and changed Drive files and again for Drive Documents still pending or failed after REQUEUE_AFTER; email
# attachments are classified by the Email Ingestion pipeline (DocumentsClassify). With +force: true+ an already
# classified Document is classified again (its llm taggings replaced).
#
# Returns early, with no LLM call, for a Document that is already classified, so duplicates queued by a slow queue are
# no-ops. RubyLLM already retries HTTP-level failures, so a RubyLLM::Error is final for this run (the Document is
# marked failed); transport errors (ApplicationJob::TRANSPORT_ERRORS, re-raised by the service) get one outer retry.
class Document::TagJob < ApplicationJob
  queue_as :default

  # How long a Document may stay pending or failed before Document::SyncDriveJob queues its tagging again.
  REQUEUE_AFTER = 1.hour
  TRANSPORT_ERRORS = ApplicationJob::TRANSPORT_ERRORS

  discard_on ActiveRecord::RecordNotFound
  retry_on(*TRANSPORT_ERRORS, wait: 5.seconds, attempts: 2) do |job, error|
    Rails.logger.error("[Document::TagJob] document #{job.arguments.first} transport error after retries: #{error.message}")
  end

  def perform(document_id, force: false)
    result = Tags::Classify.call(Document.find(document_id), force:)
    Rails.logger.error("[Document::TagJob] tagging document #{document_id} failed: #{result.error}") if result.status == "failed"
  end
end
