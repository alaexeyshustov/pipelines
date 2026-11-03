module Emails
  module Adapters
    # Read-only INBOX queries behind the incremental sync (ADR 0013): UIDVALIDITY, UID listings and full messages.
    class ImapInboxReader
      MAILBOX = "INBOX".freeze

      # ["<uid_validity>" as Integer, or nil for a legacy bare UID, uid]
      def self.split_message_id(message_id)
        validity, uid = message_id.to_s.split(":", 2)
        uid ? [ validity.to_i, uid.to_i ] : [ nil, validity.to_i ]
      end

      def initialize(session)
        @session = session
      end

      def uid_validity
        @session.with_lock { @session.imap.status(MAILBOX, [ "UIDVALIDITY" ]).fetch("UIDVALIDITY").to_i }
      end

      # `UID n:*` always matches the last message even when it is older than n, so UIDs <= +last_uid+ are dropped.
      def uids_after(last_uid)
        search([ "UID", "#{last_uid + 1}:*" ]).select { |uid| uid > last_uid }
      end

      def uids_since(date)
        search(ImapSearchCriteria.new(after_date: date).build)
      end

      # The parsed RFC822 message, or nil when the UID does not exist.
      def mail(uid)
        raw = @session.with_lock do
          @session.ensure_mailbox(MAILBOX)
          @session.fetch_raw_mail(uid, YahooAdapter::FULL_FIELDS)
        end
        raw.blank? ? nil : Mail.new(raw)
      end

      private

      def search(criteria)
        @session.with_lock do
          @session.ensure_mailbox(MAILBOX)
          @session.imap.uid_search(criteria).sort
        end
      end
    end
  end
end
