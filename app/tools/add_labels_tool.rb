  class AddLabelsTool < RubyLLM::Tool
    description "Add one or more labels/flags to a specific email. " \
                'Gmail: use label IDs (e.g. "STARRED"). ' \
                'Yahoo: use IMAP flags (e.g. "\\Flagged", "\\Seen").'

    param :provider,   type: :string, desc: 'Email provider: "gmail" or "yahoo"', required: true
    param :message_id, type: :string, desc: "The message ID (Gmail string ID or Yahoo IMAP UID as string).", required: true
    param :label_ids,  type: :array,  desc: 'Array of label IDs or IMAP flags to add (e.g. ["STARRED"] or ["\\\\Flagged"]).', required: true
    param :mailbox,    type: :string, desc: "Yahoo: mailbox/folder containing the message. Defaults to INBOX.", required: false

    def execute(provider:, message_id:, label_ids:, mailbox: "INBOX")
      Emails.modify_labels(provider, message_id, add: label_ids, mailbox: mailbox)
    end
  end
