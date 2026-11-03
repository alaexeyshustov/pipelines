module Records
  class NormalizeJob < ApplicationJob
    def perform(ids)
      interviews = Interview.where(id: ids)
      input = {
        records_to_normalize: interviews.map(&:attributes),
        destination_table:    "interviews",
        columns_to_normalize: %w[company job_title]
      }.to_json

      Orchestration::Agents::RecordsNormalizer.new.ask(input)
    end
  end
end
