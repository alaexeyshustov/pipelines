module Orchestration
  module Executors
    # Steps 2 and 5 of the Email Ingestion pipeline: classify (Tags::Classify) the pending and failed records among
    # the ids received, and report them as tagged, untagged or failed. Records that are already classified are left
    # alone.
    module ClassifyRecords
      include PerRecord

      CLASSIFY_OUTPUT = {
        tagged: PerRecord::ID_LIST,
        untagged: PerRecord::ID_LIST,
        failed: PerRecord::FAILED_LIST
      }.freeze

      private

      def classify(model, ids)
        statuses = Hash.new # : Hash[Integer, String]
        failed = Array.new # : Array[json_object]
        each_record(model.where(classification_status: %w[pending failed]), ids, failed) do |record|
          result = Tags::Classify.call(record)
          statuses[record.id] = result.status
          failed << failure(record.id, result.error.to_s) if result.status == "failed"
        end
        { "tagged" => ids_with(statuses, "tagged"), "untagged" => ids_with(statuses, "untagged"), "failed" => failed }
      end

      def ids_with(statuses, status)
        statuses.select { |_id, value| value == status }.keys
      end
    end
  end
end
