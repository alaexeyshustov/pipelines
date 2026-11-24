module Orchestration
  module Executors
    # Step 5 of the Email Ingestion pipeline (ADR 0018): Tags::Classify for each pending or failed document among the
    # ids of step 4. Drive documents are classified by Document::TagJob instead.
    class DocumentsClassify
      include Orchestration::Executable
      include ClassifyRecords

      input_schema(document_ids: PerRecord::ID_LIST)
      output_schema(**ClassifyRecords::CLASSIFY_OUTPUT)

      def self.call(document_ids:, **_kwargs)
        new(document_ids:).execute
      end

      def initialize(document_ids:, **_kwargs)
        @document_ids = document_ids
      end

      def execute
        classify(Document, @document_ids)
      end
    end
  end
end
