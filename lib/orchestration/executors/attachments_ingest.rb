module Orchestration
  module Executors
    # Step 4 of the Email Ingestion pipeline (ADR 0018): Document::IngestEmailAttachments for each tagged Gmail email
    # among the ids that has no document yet (a re-listed email is not downloaded again, so a failed attachment is not
    # retried). Other emails are listed as skipped (Yahoo has no attachment listing; only tagged emails are ingested).
    # +document_ids+ holds the documents the service returned plus the ones the listed tagged Gmail emails already
    # have, so a pending or failed document from an earlier run reaches the classify and embed steps. A failed
    # attachment is reported as { "id" => email id, "error" => "<filename>: <class>: <message>" }.
    class AttachmentsIngest
      include Orchestration::Executable
      include PerRecord

      input_schema(email_ids: PerRecord::ID_LIST)
      output_schema(document_ids: PerRecord::ID_LIST, skipped: PerRecord::ID_LIST, failed: PerRecord::FAILED_LIST)

      def self.call(email_ids:, **_kwargs)
        new(email_ids:).execute
      end

      def initialize(email_ids:, **_kwargs)
        @email_ids = email_ids
      end

      def execute
        document_ids = Array.new # : Array[Integer]
        failed = Array.new # : Array[json_object]
        each_record(unprocessed, @email_ids, failed) { |email| ingest(email, document_ids, failed) }
        { "document_ids" => (document_ids + existing_document_ids).uniq, "skipped" => skipped_ids, "failed" => failed }
      end

      private

      def ingest(email, document_ids, failed)
        result = Document::IngestEmailAttachments.call(email)
        document_ids.concat(result.document_ids)
        result.failed.each { |message| failed << failure(email.id, message) }
      end

      def skipped_ids
        Email.where(id: @email_ids).where.not(id: eligible.select(:id)).ids
      end

      def eligible
        Email.tagged.where(provider: Emails::GMAIL)
      end

      # Emails without a document are the ones never ingested; one that has documents is not downloaded again, so a
      # failed attachment is not retried (its document, if any, still goes on to steps 5 and 6).
      def unprocessed
        eligible.where.not(id: Document.where.not(email_id: nil).select(:email_id))
      end

      def existing_document_ids
        Document.where(email_id: eligible.where(id: @email_ids).select(:id)).ids
      end
    end
  end
end
