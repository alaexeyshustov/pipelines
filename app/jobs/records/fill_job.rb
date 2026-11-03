module Records
  class FillJob < ApplicationJob
    def perform(ids)
      interviews = Interview.where(id: ids)
      input = {
        emails:            interviews.map(&:attributes),
        destination_table: "interviews"
      }.to_json

      Orchestration::Agents::RecordsFiller.new.ask(input)
    end
  end
end
