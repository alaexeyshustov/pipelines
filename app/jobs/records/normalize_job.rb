# frozen_string_literal: true

module Records
  class NormalizeJob < ApplicationJob
    def perform(ids)
      mails = ApplicationMail.where(id: ids)
      input = {
        records_to_normalize: mails.map(&:attributes),
        destination_table:    "application_mails",
        columns_to_normalize: %w[company job_title]
      }.to_json

      Records::NormalizeAgent.new.ask(input)
    end
  end
end
