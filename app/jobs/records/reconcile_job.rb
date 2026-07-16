
module Records
  class ReconcileJob < ApplicationJob
    def perform(ids)
      mails = ApplicationMail.by_ids(ids)
      input = {
        emailsto_reconcile: mails.map(&:attributes),
        destination_table:  "interviews",
        matching_columns:   %w[company job_title],
        matching_logic:     "Match by company and job_title (case-insensitive)",
        statuses:           Interview::STATUSES,
        initial_status:     Interview::STATUSES.first
      }.to_json

      Orchestration::Agents::RecordsReconciler.new.ask(input)
    end
  end
end
