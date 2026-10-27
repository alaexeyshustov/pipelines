module Emails
  class AddLabelsTool < RubyLLM::Tool
    def self.readonly? = false

    description "Add one or more labels/flags to a specific email. " \
                'Gmail: use label IDs (e.g. "STARRED"). ' \
                'Yahoo: use folder names to label messages (e.g. "applications"); ' \
                'IMAP flags like "\\Flagged" or "\\Seen" are only for starred/read state.'

    parameter :provider,   type: :string, description: 'Email provider: "gmail" or "yahoo"', required: true
    parameter :message_id, type: :string, description: "The message ID (Gmail string ID or Yahoo IMAP UID as string).", required: true
    parameter :label_ids,  type: :array,  description: 'Array of label IDs or Yahoo folder names to add (e.g. ["STARRED"] or ["applications"]). Yahoo flags like ["\\\\Flagged"] only change message state.', required: true
    parameter :mailbox,    type: :string, description: "Yahoo: source mailbox/folder containing the message, usually 'Inbox'. Do not pass the destination label here. Defaults to INBOX.", required: false

    def name = "add_labels"

    def execute(provider:, message_id:, label_ids:, mailbox: "INBOX")
      Emails.modify_labels(provider, message_id, add: label_ids, source_mailbox: mailbox)
    end
  end
end
