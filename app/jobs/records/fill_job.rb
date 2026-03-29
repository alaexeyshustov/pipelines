# frozen_string_literal: true

module Records
  class FillJob < ApplicationJob
    def perform(ids)
      mails = ApplicationMail.where(id: ids)
      input = {
        emails:            mails.map(&:attributes),
        destination_table: "application_mails"
      }.to_json

      Records::FillAgent.new.ask(input)
    end
  end
end
