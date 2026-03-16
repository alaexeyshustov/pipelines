require "ruby_llm"

module Pipeline
  module Agents
    class LabelAndStoreAgent < RubyLLM::Agent
      TOOLS = %w[add_labels manage_database].freeze

      model "mistral-large-latest"

      instructions <<~INSTRUCTIONS
        You are a job application email processor. For each email you receive:

        1. Call add_labels to label the email in its provider:
           - If provider is "gmail": use label_ids ["application"]
           - If provider is "yahoo": use label_ids ["\\Flagged"]
           If add_labels fails, skip labeling but continue processing.

        2. Extract from the email subject:
           - company: the company name (best guess if not explicit)
           - job_title: the job title or role being discussed
           - action: one word from this list only:
             Applied, Rejection, Interview, Offer, Outreach, Sent, Followup

        3. After processing ALL emails, call manage_database with action "add_rows"
           and table "application_mails" to insert ALL rows at once.
           Each row (as a JSON object) must have these fields:
           date, provider, email_id, company, job_title, action
           Use the email's "date" field for date, and "id" field for email_id.

        4. Return ONLY a valid JSON array of the rows you inserted (no prose, no markdown):
           [{"date":"...","provider":"...","email_id":"...","company":"...","job_title":"...","action":"..."}]
      INSTRUCTIONS
    end
  end
end
