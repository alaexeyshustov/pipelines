module Emails
  class AddLabelsTool < RubyLLM::Tool
    def self.readonly? = false

    description "Add one or more labels/flags to a specific email. " \
                'Gmail: use label IDs (e.g. "STARRED"). ' \
                'Yahoo: use folder names to label messages (e.g. "applications"); ' \
                'IMAP flags like "\\Flagged" or "\\Seen" are only for starred/read state.'

    param :provider,   type: :string, desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :message_id, type: :string, desc: "The message ID (Gmail string ID or Yahoo IMAP UID as string).", required: true
    param :label_ids,  type: :array,  desc: 'Array of label IDs or Yahoo folder names to add (e.g. ["STARRED"] or ["applications"]). Yahoo flags like ["\\\\Flagged"] only change message state.', required: true
    param :mailbox,    type: :string, desc: "Yahoo: source mailbox/folder containing the message, usually 'Inbox'. Do not pass the destination label here. Defaults to INBOX.", required: false

    def name = "add_labels"

    def execute(provider:, message_id:, label_ids:, mailbox: "INBOX")
      Emails.modify_labels(provider, message_id, add: label_ids, source_mailbox: mailbox)
    end
  end
end
