module Orchestration
  module Executors
    # Step 2 of the Email Ingestion pipeline (ADR 0018): Tags::Classify for each pending or failed email among the
    # ids of step 1. Per-email failures are reported in the output, they do not fail the step.
    class EmailsClassify
      include Orchestration::Executable
      include ClassifyRecords

      input_schema(email_ids: PerRecord::ID_LIST)
      output_schema(**ClassifyRecords::CLASSIFY_OUTPUT)

      def self.call(email_ids:, **_kwargs)
        new(email_ids:).execute
      end

      def initialize(email_ids:, **_kwargs)
        @email_ids = email_ids
      end

      def execute
        classify(Email, @email_ids)
      end
    end
  end
end
