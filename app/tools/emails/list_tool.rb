module Emails
  class ListTool < RubyLLM::Tool
    def self.readonly? = true

    description "List recent emails from Gmail or Yahoo Mail inbox."

    parameter :provider,     type: :string,  description: 'Email provider: "gmail" or "yahoo"', required: true
    parameter :max_results,  type: :integer, description: "Number of emails to return (1-100). Defaults to 10.", required: false
    parameter :after_date,   type: :string,  description: "Return emails after this date (YYYY-MM-DD format).", required: false
    parameter :before_date,  type: :string,  description: "Return emails before this date (YYYY-MM-DD format).", required: false
    parameter :offset,       type: :integer, description: "Number of emails to skip (for pagination). Defaults to 0.", required: false
    parameter :label,        type: :string,  description: 'Gmail: filter by label name (e.g. "INBOX", "UNREAD"). Yahoo: mailbox/folder name (e.g. "INBOX", "Sent"). Defaults to INBOX.', required: false

    def name = "list_emails"

    def execute(provider:, max_results: 10, after_date: nil, before_date: nil, offset: 0, label: nil)
      parsed_after  = after_date  ? Date.parse(after_date)  : nil
      parsed_before = before_date ? Date.parse(before_date) : nil

      Emails.list_messages(
        provider,
        max_results:  max_results,
        after_date:   parsed_after,
        before_date:  parsed_before,
        offset:       offset,
        label:        label
      )
    end
  end
end
