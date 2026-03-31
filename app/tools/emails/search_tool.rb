module Emails
  class SearchTool < RubyLLM::Tool
    description "Search Gmail or Yahoo Mail using a query string and return matching emails."

    param :provider,    type: :string,  desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :query,       type: :string,  desc: "Search query (e.g. 'from:boss@example.com', 'subject:invoice', 'is:unread')", required: true
    param :max_results, type: :integer, desc: "Maximum number of results to return (1-100). Defaults to 10.", required: false
    param :offset,      type: :integer, desc: "Number of results to skip (for pagination). Defaults to 0.", required: false
    param :label,       type: :string,  desc: "Yahoo: mailbox/folder to search. Defaults to INBOX. Gmail: label name to search. Defaults - any", required: false

    def name = "search_emails"

    def execute(provider:, query:, max_results: 10, label: nil)
      Emails.search_messages(provider, query, max_results:, label:)
    end
  end
end
