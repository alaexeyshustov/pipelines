module Orchestration
  module Executors
    # Pipeline step: incremental INBOX sync of every provider (see Email::SyncInboxJob, ADR 0013). Each provider runs
    # inline and independently: one failing does not stop the other. A provider without credentials is reported as
    # skipped, not failed. After all ran, any failure raises ProviderFailure so the step run is failed.
    #
    # A failed action run keeps no output (only its error text), so the raise carries the per-provider output as
    # JSON in its message; otherwise the counts of the provider that succeeded would be lost.
    #
    # Output per provider: the job's counts (mode, fetched, stored, duplicates, failed) plus "enqueued", the number of
    # processing jobs enqueued for the new emails (0 until that step exists).
    class EmailsSync
      include Orchestration::Executable

      PROVIDERS = %w[gmail yahoo].freeze
      MISSING_CREDENTIALS = /\AMissing (Gmail|Yahoo) credentials/
      SKIPPED = { "skipped" => true, "reason" => "no credentials" }.freeze

      class ProviderFailure < StandardError; end

      def self.call(**_kwargs)
        failures = {} # : Hash[String, String]
        output = PROVIDERS.index_with { |provider| sync(provider, failures) }
        return output if failures.empty?

        raise ProviderFailure, failure_message(failures, output)
      end

      def self.sync(provider, failures)
        counts = Email::SyncInboxJob.perform_now(provider).counts
        failures[provider] = "#{counts.fetch('failed')} message(s) failed" if counts.fetch("failed").positive?
        counts.merge("enqueued" => 0)
      rescue StandardError => error
        return SKIPPED.dup if MISSING_CREDENTIALS.match?(error.message)

        failures[provider] = "#{error.class}: #{error.message}"
        { "failed" => true }
      end
      private_class_method :sync

      def self.failure_message(failures, output)
        reasons = failures.map { |provider, reason| "#{provider}: #{reason}" }.join("; ")
        "Email sync failed (#{reasons}). Output: #{output.to_json}"
      end
      private_class_method :failure_message
    end
  end
end
