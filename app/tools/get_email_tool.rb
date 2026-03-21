  class GetEmailTool < RubyLLM::Tool
    description "Get the full content of a specific email by its message ID or IMAP UID."

    param :provider,   type: :string, desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :message_id, type: :string, desc: "The message ID (Gmail string ID or Yahoo IMAP UID as string).", required: true
    param :mailbox,    type: :string, desc: "Yahoo: mailbox/folder containing the message. Defaults to INBOX.", required: false

    def execute(provider:, message_id:, mailbox: "INBOX")
      Emails.get_message(provider, message_id, mailbox: mailbox)
    end
  end
