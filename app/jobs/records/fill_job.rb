# frozen_string_literal: true

module Records
  class FillJob < ApplicationJob
    def perform(ids)
      mails = ApplicationMail.by_ids(ids)
      input = {
        emails:            mails.map(&:attributes),
        destination_table: "application_mails"
      }.to_json

      Orchestration::Agents::RecordsFiller.new.ask(input)
    end
  end
end
