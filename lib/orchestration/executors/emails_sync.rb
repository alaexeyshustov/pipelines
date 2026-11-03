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
    # Output per provider: the job's counts (mode, fetched, stored, duplicates, failed) plus "enqueued", the total
    # number of Email::ProcessJob enqueued, and "requeued", the part of it that were stale untagged emails.
    class EmailsSync
      include Orchestration::Executable

      PROVIDERS = %w[gmail yahoo].freeze
      MISSING_CREDENTIALS = /\AMissing (Gmail|Yahoo) credentials/
      REQUEUE_AFTER = 1.hour
      SKIPPED = { "skipped" => true, "reason" => "no credentials" }.freeze

      class ProviderFailure < StandardError; end

      def self.call(**_kwargs)
        failures = {} # : Hash[String, String]
        output = PROVIDERS.index_with { |provider| sync(provider, failures) }
        return output if failures.empty?

        raise ProviderFailure, failure_message(failures, output)
      end

      def self.sync(provider, failures)
        result = Email::SyncInboxJob.perform_now(provider)
        counts = result.counts
        failures[provider] = "#{counts.fetch('failed')} message(s) failed" if counts.fetch("failed").positive?
        counts.merge(enqueue_processing(provider, result.email_ids))
      rescue StandardError => error
        return SKIPPED.dup if MISSING_CREDENTIALS.match?(error.message)

        failures[provider] = "#{error.class}: #{error.message}"
        { "failed" => true }
      end
      private_class_method :sync

      def self.enqueue_processing(provider, new_email_ids)
        stale_ids = Email.awaiting_tagging(before: REQUEUE_AFTER.ago).where(provider: provider)
                         .where.not(id: new_email_ids).pluck(:id) # : Array[Integer]
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
