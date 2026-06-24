module Emails
  module Adapters
    class YahooMessageParser
      def initialize(uid, mail, mailbox)
        @uid     = uid
        @mail    = mail
        @mailbox = mailbox
      end

      def to_h
        decoded = @mail.body&.decoded # : String?
        {
          id:       @uid.to_s,
          provider: "yahoo",
          subject:  decode_subject,
          from:     format_addresses(@mail.from),
          to:       format_addresses(@mail.to),
          date:     @mail.date&.to_s || "Unknown",
          snippet:  decoded.to_s[0, 200],
          labels:   [ @mailbox ]
        }
      end

      private

      def decode_subject
        ImapBodyParser.decode_header(@mail.subject) || "(No Subject)"
      end

      def format_addresses(addresses)
        Array(addresses).join(", ").presence || "Unknown"
      end
    end
  end
end
