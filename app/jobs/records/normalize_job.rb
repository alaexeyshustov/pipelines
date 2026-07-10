# frozen_string_literal: true

module Records
  class NormalizeJob < ApplicationJob
    def perform(ids)
      mails = ApplicationMail.by_ids(ids)
      input = {
        records_to_normalize: mails.map(&:attributes),
        destination_table:    "application_mails",
        columns_to_normalize: %w[company job_title]
      }.to_json

      Orchestration::Agents::RecordsNormalizer.new.ask(input)
    end
  end
end
