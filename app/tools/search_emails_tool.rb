  class SearchEmailsTool < RubyLLM::Tool
    description "Search Gmail or Yahoo Mail using a query string and return matching emails."

    param :provider,    type: :string,  desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :query,       type: :string,  desc: "Search query (e.g. 'from:boss@example.com', 'subject:invoice', 'is:unread')", required: true
    param :max_results, type: :integer, desc: "Maximum number of results to return (1-100). Defaults to 10.", required: false
    param :mailbox,     type: :string,  desc: "Yahoo: mailbox/folder to search. Defaults to INBOX.", required: false


    def execute(provider:, query:, max_results: 10, mailbox: "INBOX")
      Emails.search_messages(provider, query, max_results: max_results, mailbox: mailbox)
    end
  end
