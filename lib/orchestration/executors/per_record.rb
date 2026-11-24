module Orchestration
  module Executors
    # The loop shared by the per-record steps of the Email Ingestion pipeline (ADR 0018). Each record is handled on
    # its own, so the step can later fan out per record (#241): a failure is recorded as { "id", "error" } and the
    # loop goes on; every record starts with a heartbeat, so a long step does not look like a dead run.
    module PerRecord
      ID_LIST = { "type" => "array", "items" => { "type" => "integer" } }.freeze
      FAILED_LIST = {
        "type" => "array",
        "items" => { "type" => "object", "properties" => { "id" => { "type" => "integer" }, "error" => { "type" => "string" } } }
      }.freeze

      private

      # Yields each record of +scope+ whose id is in +ids+, once, in the order of +ids+. An exception from the block is
      # appended to +failed+.
      def each_record(scope, ids, failed)
        records = scope.where(id: ids).index_by(&:id)
        ids.uniq.filter_map { |id| records[id] }.each do |record|
          Orchestration::Heartbeat.beat
          yield record
        rescue StandardError => error
          failed << failure(record.id, "#{error.class}: #{error.message}")
        end
      end

      def failure(id, message)
        { "id" => id, "error" => message }
      end
    end
  end
end
