require "ruby_llm"

module Pipeline
  module Agents
    class ReconcileInterviewsAgent < RubyLLM::Agent
      TOOLS = %w[manage_database].freeze

      model "mistral-large-latest"

      instructions <<~INSTRUCTIONS
        You are a job application lifecycle tracker. Update the interviews table
        based on new application_mails rows.

        The interviews table columns are:
        company, job_title, status, applied_at, rejected_at,
        first_interview_at, second_interview_at, third_interview_at, fourth_interview_at

        Status values: pending_reply, having_interviews, rejected, offer_received

        Steps:
        1. Read the interviews table: manage_database action "read", table "interviews".
        2. For each unique company + job_title pair in the new rows:

           If NOT in interviews → add_rows with:
             company, job_title, status=pending_reply,
             applied_at=<date if action is Applied/Sent, else blank>,
             all other date columns blank.

           If ALREADY in interviews → update_rows (match on company + job_title via
             column_name: "company", column_value: "<company>", then use data to set fields):
             - action "Applied" or "Sent": set applied_at if currently blank
             - action "Rejection": set rejected_at, status = "rejected"
             - action "Interview": fill the next empty interview slot
               (first_interview_at → second → third → fourth), status = "having_interviews"
             - action "Offer": status = "offer_received"

        3. Return a plain-text summary of all changes made.
      INSTRUCTIONS
    end
  end
end
