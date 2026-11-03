module Emails
  module Adapters
    # The adapter methods behind the incremental INBOX sync (ADR 0013). Mixed into YahooAdapter, which provides
    # +@account+ (the login name) and +@inbox+ (an ImapInboxReader).
    module YahooInboxSync
      # The login name, which identifies the mailbox in a sync cursor.
      def account
        @account
      end

      # INBOX UIDVALIDITY: UIDs are only comparable while it stays the same.
      def inbox_uid_validity
        @inbox.uid_validity
      end

      # UIDs of INBOX messages newer than +last_uid+, ascending.
      def inbox_uids_after(last_uid)
        @inbox.uids_after(last_uid)
      end

      # UIDs of INBOX messages received on or after +date+, ascending.
      def inbox_uids_since(date)
        @inbox.uids_since(date)
      end

      # A message with +body+, +html_body+, a parsed +date+ (Time) and a "<uid_validity>:<uid>" id. A bare UID is
      # prefixed with the current INBOX UIDVALIDITY.
      def fetch_message(message_id)
        validity, uid = ImapInboxReader.split_message_id(message_id)
        mail = @inbox.mail(uid) || raise("Message not found: #{message_id}")

        YahooFullMessage.new(validity || inbox_uid_validity, uid, mail).to_h
      end
    end
  end
end
