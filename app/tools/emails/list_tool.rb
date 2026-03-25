module Emails
  class ListTool < RubyLLM::Tool
    description "List recent emails from Gmail or Yahoo Mail inbox."

    param :provider,     type: :string,  desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :max_results,  type: :integer, desc: "Number of emails to return (1-100). Defaults to 10.", required: false
    param :query,        type: :string,  desc: "Search query (e.g. 'is:unread', 'from:john@example.com')", required: false
    param :after_date,   type: :string,  desc: "Return emails after this date (YYYY-MM-DD format).", required: false
    param :before_date,  type: :string,  desc: "Return emails before this date (YYYY-MM-DD format).", required: false
    param :offset,       type: :integer, desc: "Number of emails to skip (for pagination). Defaults to 0.", required: false
    param :label,        type: :string,  desc: 'Gmail: filter by label ID or name (e.g. "INBOX", "UNREAD").', required: false
    param :mailbox,      type: :string,  desc: 'Yahoo: mailbox/folder name (e.g. "INBOX", "Sent"). Defaults to INBOX.', required: false

    def name = "list_emails"

    def execute(provider:, max_results: 10, query: nil, after_date: nil, before_date: nil,
                offset: 0, label: nil, mailbox: "INBOX")
      parsed_after  = after_date  ? Date.parse(after_date)  : nil
      parsed_before = before_date ? Date.parse(before_date) : nil

      Emails.list_messages(
        provider,
        max_results:  max_results,
        query:        query,
        after_date:   parsed_after,
        before_date:  parsed_before,
        offset:       offset,
        label:        label,
        mailbox:      mailbox
      )
    end
  end
end
