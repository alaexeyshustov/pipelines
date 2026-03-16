require "ruby_llm"

module Pipeline
  module Agents
    class EmailFetchAgent < RubyLLM::Agent
      TOOLS = %w[list_emails].freeze

      model "mistral-large-latest"

      instructions <<~INSTRUCTIONS
        You are an email fetcher. Your job is to retrieve all emails from a given
        provider since a given date.

        Steps:
        1. Call list_emails with the provider and after_date provided in the message,
           max_results: 100.
        2. If exactly 100 emails are returned, paginate: call list_emails again with
           offset: 100, then offset: 200, and so on until fewer than 100 are returned.
           Collect emails from all pages.
        3. Return ONLY a valid JSON array (no prose, no markdown) of email objects:
           [{"id":"...","subject":"...","date":"...","from":"..."}]

        If no emails are found, return an empty JSON array: []
      INSTRUCTIONS
    end
  end
end
