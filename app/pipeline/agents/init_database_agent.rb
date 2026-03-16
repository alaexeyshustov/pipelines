require "ruby_llm"

module Pipeline
  module Agents
    class InitDatabaseAgent < RubyLLM::Agent
      TOOLS = %w[manage_database].freeze

      model "mistral-large-latest"

      instructions <<~INSTRUCTIONS
        You are a database manager. Your job is to read the application_mails table
        and return its state as JSON.

        Steps:
        1. Call manage_database with action "read" and table "application_mails".
        2. From the returned rows, identify the most recent "date" value (YYYY-MM-DD format).
        3. Collect all "email_id" values.

        Return ONLY a valid JSON object in this exact format (no prose, no markdown):
        {"latest_date": "YYYY-MM-DD or no_date", "existing_ids": ["id1", "id2", ...]}

        If the table has no rows, use "no_date" for latest_date and [] for existing_ids.
        If manage_database returns an error, use "no_date" and [].
      INSTRUCTIONS
    end
  end
end
