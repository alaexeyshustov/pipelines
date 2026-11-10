module Orchestration
  module Executors
    # Pipeline step: incremental INBOX sync of every provider (see Email::SyncInboxJob, ADR 0013). Each provider runs
    # inline and independently: one failing does not stop the other. A provider without credentials is reported as
    # skipped, not failed. After all ran, any failure raises ProviderFailure so the step run is failed.
    #
    # A failed action run keeps no output (only its error text), so the raise carries the per-provider output as
    # JSON in its message; otherwise the counts of the provider that succeeded would be lost.
    #
    # Enqueueing lives here, not in the job: the job returns the ids of the newly stored emails (never duplicates) and
    # this step enqueues Email::ProcessJob for each, plus for the provider's emails still untagged (tagged_at IS NULL)
    # after REQUEUE_AFTER, so a failed tagging is retried by the next run.
    #
    # Once per run, outside the provider loop, the same step retries the email-attachment Documents that are still
    # untagged (tagged_at IS NULL) after Document::TagJob::REQUEUE_AFTER, by queueing Document::TagJob: attachments
    # only come from the emails pipeline, so this is the scheduled step that sees them (Drive Documents are retried by
    # Document::SyncDriveJob).
    #
    # Output per provider: the job's counts (mode, fetched, stored, duplicates, failed) plus "enqueued", the total
    # number of Email::ProcessJob enqueued, and "requeued", the part of it that were stale untagged emails. One
    # top-level "documents_requeued" is the number of Document::TagJob enqueued for stale untagged attachments.
    class EmailsSync
      include Orchestration::Executable

      PROVIDERS = Emails::PROVIDER_NAMES
      REQUEUE_AFTER = 1.hour
      SKIPPED = { "skipped" => true, "reason" => "no credentials" }.freeze

      class ProviderFailure < StandardError; end

      def self.call(**_kwargs)
        failures = {} # : Hash[String, String]
        stale = stale_email_ids
        output = PROVIDERS.index_with { |provider| sync(provider, failures, stale.fetch(provider, [])) }
        output = output.merge("documents_requeued" => requeue_documents)
        return output if failures.empty?

        raise ProviderFailure, failure_message(failures, output)
      end

      def self.sync(provider, failures, stale_ids)
        result = Email::SyncInboxJob.perform_now(provider)
        counts = result.counts
        failures[provider] = "#{counts.fetch('failed')} message(s) failed" if counts.fetch("failed").positive?
        counts.merge(enqueue_processing(result.email_ids, stale_ids))
      rescue Emails::NotConfigured
        SKIPPED.dup
      rescue StandardError => error
        failures[provider] = "#{error.class}: #{error.message}"
        { "failed" => true }
      end
      private_class_method :sync

      # Untagged emails older than REQUEUE_AFTER per provider, in one query.
      def self.stale_email_ids
        Email.awaiting_tagging(before: REQUEUE_AFTER.ago).where(provider: PROVIDERS)
             .pluck(:provider, :id).group_by(&:first).transform_values { |rows| rows.map(&:last) } # : Hash[String, Array[Integer]]
      end
      private_class_method :stale_email_ids

      # Queues Document::TagJob for the untagged email-attachment Documents older than Document::TagJob::REQUEUE_AFTER;
      # returns how many.
      def self.requeue_documents
        ids = Document.awaiting_tagging(before: Document::TagJob::REQUEUE_AFTER.ago).where.not(email_id: nil).pluck(:id)
        ids.each { |document_id| Document::TagJob.perform_later(document_id) }
        ids.size
      end
      private_class_method :requeue_documents

      def self.enqueue_processing(new_email_ids, stale_ids)
        stale_ids -= new_email_ids
        (new_email_ids + stale_ids).each { |email_id| Email::ProcessJob.perform_later(email_id) }
        { "enqueued" => new_email_ids.size + stale_ids.size, "requeued" => stale_ids.size }
      end
      private_class_method :enqueue_processing

      def self.failure_message(failures, output)
        reasons = failures.map { |provider, reason| "#{provider}: #{reason}" }.join("; ")
        "Email sync failed (#{reasons}). Output: #{output.to_json}"
      end
      private_class_method :failure_message
    end
  end
end
