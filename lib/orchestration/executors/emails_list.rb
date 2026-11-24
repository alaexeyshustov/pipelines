module Orchestration
  module Executors
    # Step 1 of the Email Ingestion pipeline (ADR 0018): reads the requested providers with Email::InboxSync, one after
    # another (SQLite cursor writes stay serial). The dates are the run's only input; without them each provider
    # continues from its sync cursor. A provider without credentials is reported as skipped, any other provider error
    # as failed, and neither stops the others; the step fails only when no requested provider worked.
    #
    # A failed action run keeps no output (only its error text), so the raise carries the per-provider output as JSON
    # in its message.
    #
    # +email_ids+ is the unique union of the new emails, the pending and failed emails of the requested providers (no
    # date filter: emails.date is the Date: header, not the received date) and the tagged emails with no embedding for
    # the current model, so a re-run finishes what an earlier one left undone.
    class EmailsList
      include Orchestration::Executable

      DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

      class ProviderFailure < StandardError; end

      input_schema(
        providers: {
          "type" => "array", "items" => { "type" => "string", "enum" => Emails::PROVIDER_NAMES }, "minItems" => 1,
          "description" => "Mailboxes to read."
        },
        date_from: { "description" => "Received on or after. Leave empty to fetch mail received since the last sync." },
        date_to: { "description" => "Received on or before. Leave empty for up to now." }
      )
      output_schema(
        email_ids: PerRecord::ID_LIST,
        providers: { "type" => "object", "description" => "Per provider: mode (the one attempted, when it failed), counts and, when it failed, the error." }
      )

      def self.call(providers:, date_from: nil, date_to: nil, **_kwargs)
        new(providers:, date_from:, date_to:).execute
      end

      # Shown next to the run form's fields: the last sync per provider, from one query.
      def self.run_hints
        synced = Email::SyncCursor.group(:provider).maximum(:last_synced_at)
        list = Emails::PROVIDER_NAMES.map { |provider| "#{provider} #{synced[provider]&.in_time_zone&.strftime('%Y-%m-%d %H:%M') || 'never'}" }
        { "providers" => "Last synced: #{list.join(', ')}" }
      end

      def initialize(providers:, date_from: nil, date_to: nil, **_kwargs)
        @providers = providers
        @date_from = date_from
        @date_to = date_to
      end

      def execute
        providers, date_from, date_to = validated_input
        new_ids = Array.new # : Array[Integer]
        report = providers.index_with { |provider| list(provider, date_from, date_to, new_ids) }
        output = { "email_ids" => (new_ids + backlog_ids(providers)).uniq, "providers" => report }
        raise ProviderFailure, failure_message(report, output) if report.values.none? { |entry| worked?(entry) }

        output
      end

      private

      def list(provider, date_from, date_to, new_ids)
        Orchestration::Heartbeat.beat
        result = Email::InboxSync.call(provider:, date_from:, date_to:)
        new_ids.concat(result.email_ids)
        result.counts.merge("mode" => result.mode)
      rescue Emails::NotConfigured
        { "mode" => "skipped" }
      rescue Email::InboxSync::Failure => error
        failed_entry(error.mode, error.message)
      rescue StandardError => error
        failed_entry("unknown", "#{error.class}: #{error.message}")
      end

      # The mode that was attempted ("unknown" when the error came before one was picked), zero counts and the error.
      def failed_entry(mode, message)
        { "mode" => mode, "fetched" => 0, "stored" => 0, "duplicates" => 0, "failed" => 0, "error" => message }
      end

      def worked?(entry)
        entry["mode"] != "skipped" && !entry.key?("error")
      end

      def backlog_ids(providers)
        awaiting = Email.where(provider: providers, classification_status: %w[pending failed]).ids
        awaiting + Email.without_embedding(model: LlmModels.embedding).where(classification_status: "tagged").ids
      end

      def failure_message(report, output)
        reasons = report.filter_map { |provider, entry| "#{provider}: #{entry['error'] || entry['mode']}" unless worked?(entry) }
        "Email list failed (#{reasons.join('; ')}). Output: #{output.to_json}"
      end

      # [providers, date_from, date_to]; raises ArgumentError for anything the run form's schema cannot express.
      def validated_input
        providers = validated_providers
        date_from = parse_date(@date_from, "date_from")
        date_to = parse_date(@date_to, "date_to")
        validate_dates(date_from, date_to)
        [ providers, date_from, date_to ]
      end

      def validated_providers
        providers = Array(@providers).uniq
        raise ArgumentError, "providers must name at least one of #{Emails::PROVIDER_NAMES.join(', ')}" if providers.empty?

        unknown = providers - Emails::PROVIDER_NAMES
        raise ArgumentError, "unknown providers: #{unknown.join(', ')} (use #{Emails::PROVIDER_NAMES.join(', ')})" if unknown.any?

        providers
      end

      def validate_dates(date_from, date_to)
        raise ArgumentError, "date_to needs date_from" if date_to && !date_from
        raise ArgumentError, "date_from must not be after date_to" if date_from && date_to && date_from > date_to

        reject_future("date_from", date_from)
        reject_future("date_to", date_to)
      end

      def reject_future(field, date)
        raise ArgumentError, "#{field} must not be in the future" if date && date > Date.current
      end

      # nil for blank, else the Date of an ISO "YYYY-MM-DD" string.
      def parse_date(value, field)
        return value if value.is_a?(Date)
        return nil if value.blank?

        raise ArgumentError, "#{field} must be a date like 2026-03-31" unless value.to_s.match?(DATE_FORMAT)

        begin
          Date.iso8601(value.to_s)
        rescue ArgumentError
          raise ArgumentError, "#{field} must be a real date like 2026-03-31"
        end
      end
    end
  end
end
