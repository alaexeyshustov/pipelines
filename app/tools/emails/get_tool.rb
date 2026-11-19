module Emails
  class GetTool < RubyLLM::Tool
    def self.readonly? = true

    BODY_LIMIT_BYTES = 32 * 1024
    TRUNCATION_MARKER = "... [truncated]".freeze

    description "Get the full content of a specific email by its message ID or IMAP UID. Long bodies are truncated to 32 KB."

    parameter :provider,   type: :string, description: 'Email provider: "gmail" or "yahoo"', required: true
    parameter :message_id, type: :string, description: "The message ID (Gmail string ID or Yahoo IMAP UID as string).", required: true
    parameter :label,    type: :string, description: "Yahoo: mailbox/folder containing the message. Defaults to INBOX. Gmail: label name to filter by (e.g. 'INBOX', 'UNREAD')", required: false

    def name = "get_email"

    def execute(provider:, message_id:, label: nil)
      return { error: "Unknown provider #{provider.inspect}. Use one of: #{Emails::PROVIDER_NAMES.join(', ')}" } unless Emails::PROVIDER_NAMES.include?(provider)

      cap_body(Emails.message(provider, message_id, label:))
    end

    private

    def cap_body(message)
      body = message[:body]
      return message unless body.is_a?(String) && body.bytesize > BODY_LIMIT_BYTES

      message.merge(body: body.truncate_bytes(BODY_LIMIT_BYTES, omission: TRUNCATION_MARKER)) # : Emails::message
    end
  end
end
