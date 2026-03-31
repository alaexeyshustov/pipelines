module Emails
  class GetTool < RubyLLM::Tool
    CACHE_DIR = Rails.root.join("tmp/cache/emails").freeze

    description "Get the full content of a specific email by its message ID or IMAP UID."

    param :provider,   type: :string, desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :message_id, type: :string, desc: "The message ID (Gmail string ID or Yahoo IMAP UID as string).", required: true
    param :label,    type: :string, desc: "Yahoo: mailbox/folder containing the message. Defaults to INBOX. Gmail: label name to filter by (e.g. 'INBOX', 'UNREAD')", required: false

    def name = "get_email"

    def execute(provider:, message_id:, label: nil)
      cache_file = CACHE_DIR.join("#{provider}_#{message_id}_#{label}.json")

      if cache_file.exist?
        JSON.parse(cache_file.read, symbolize_names: true)
      else
        result = Emails.get_message(provider, message_id, label:)
        FileUtils.mkdir_p(CACHE_DIR)
        cache_file.write(result.to_json)
        result
      end
    end
  end
end
