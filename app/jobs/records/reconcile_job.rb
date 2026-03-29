# frozen_string_literal: true

module Records
  class ReconcileJob < ApplicationJob
    def perform(ids)
      mails = ApplicationMail.where(id: ids)
      input = {
        emailsto_reconcile: mails.map(&:attributes),
        destination_table:  "interviews",
        matching_columns:   %w[company job_title],
        matching_logic:     "Match by company and job_title (case-insensitive)",
        statuses:           Interview::STATUSES,
        initial_status:     Interview::STATUSES.first
      }.to_json

      Records::ReconcileAgent.create.ask(input)
    end
  end
end
