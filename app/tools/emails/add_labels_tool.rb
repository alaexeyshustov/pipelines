module Emails
  class AddLabelsTool < RubyLLM::Tool
    def self.readonly? = false

    BLOCKED_LABELS     = %w[trash spam].freeze
    ALLOWED_IMAP_FLAGS = [ "\\Flagged", "\\Seen" ].freeze

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
      rejected = label_ids.select { |label| rejected_label?(label) }
      return { error: "Labels not allowed: #{rejected.join(', ')}. Only #{ALLOWED_IMAP_FLAGS.join(' and ')} flags are permitted; TRASH and SPAM are blocked." } if rejected.any?

      Emails.modify_labels(provider, message_id, add: label_ids, source_mailbox: mailbox)
    end

    private

    def rejected_label?(label)
      normalized = label.to_s.strip.downcase
      return true if BLOCKED_LABELS.include?(normalized)

      normalized.start_with?("\\") && ALLOWED_IMAP_FLAGS.none? { |flag| flag.downcase == normalized }
    end
  end
end
