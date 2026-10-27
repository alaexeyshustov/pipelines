module Emails
  class SearchTool < RubyLLM::Tool
    def self.readonly? = true

    description "Search Gmail or Yahoo Mail using a query string and return matching emails."

    parameter :provider,    type: :string,  description: 'Email provider: "gmail" or "yahoo"', required: true
    parameter :query,       type: :string,  description: "Search query (e.g. 'from:boss@example.com', 'subject:invoice', 'is:unread')", required: true
    parameter :max_results, type: :integer, description: "Maximum number of results to return (1-100). Defaults to 10.", required: false
    parameter :offset,      type: :integer, description: "Number of results to skip (for pagination). Defaults to 0.", required: false
    parameter :label,       type: :string,  description: "Yahoo: mailbox/folder to search. Defaults to INBOX. Gmail: label name to search. Defaults - any", required: false

    def name = "search_emails"

    def execute(provider:, query:, max_results: 10, label: nil)
      Emails.search_messages(provider, query, max_results:, label:)
    end
  end
end
