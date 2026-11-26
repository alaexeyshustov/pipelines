module Orchestration
  module Executors
    # Step 6 of the Email Ingestion pipeline (ADR 0018): embeds the tagged documents among the ids that have no
    # embedding for the current model yet, one Embeddings::Embed call per document, then flags its near-duplicates
    # (Document::DetectDuplicates). +duplicates_found+ is the number of pairs flagged. Documents that are not tagged are
    # listed as skipped, and so are tagged ones without embeddable text; a document that already has an embedding
    # appears in no list. If duplicate detection raises, the document stays embedded, the detection is
    # enqueued as Document::DetectDuplicatesJob and the document id is also listed in +failed+.
    class DocumentsEmbed
      include Orchestration::Executable
      include PerRecord

      input_schema(document_ids: PerRecord::ID_LIST)
      output_schema(
        embedded: PerRecord::ID_LIST, skipped: PerRecord::ID_LIST, duplicates_found: { "type" => "integer" },
        failed: PerRecord::FAILED_LIST
      )

      def self.call(document_ids:, **_kwargs)
        new(document_ids:).execute
      end

      def initialize(document_ids:, **_kwargs)
        @document_ids = document_ids
      end

      def execute
        output = { "embedded" => [], "skipped" => skipped_ids, "duplicates_found" => 0, "failed" => [] } # : output
        each_record(unembedded, @document_ids, output["failed"]) { |document| embed(document, output) }
        output
      end

      private

      # Embeds one tagged document and flags its near-duplicates; one with no embeddable text is skipped.
      def embed(document, output)
        unless Embeddings::Embed.call([ document ]).embedded.positive?
          output["skipped"] << document.id
          return
        end

        output["embedded"] << document.id
        output["duplicates_found"] += detect_duplicates(document, output["failed"])
      end

      def skipped_ids
        Document.where(id: @document_ids).where.not(classification_status: "tagged").ids
      end

      # The document is embedded by now, so later runs skip it: a failed detection is handed to
      # Document::DetectDuplicatesJob (it retries) and reported in +failed+, not lost.
      def detect_duplicates(document, failed)
        Document::DetectDuplicates.call(document).flagged
      rescue StandardError => error
        Document::DetectDuplicatesJob.perform_later(document.id)
        failed << failure(document.id, "duplicate detection enqueued as a job after #{error.class}: #{error.message}")
        0
      end

      def unembedded
        Document.without_embedding(model: LlmModels.embedding).where(classification_status: "tagged")
      end
    end
  end
end
