module Emails
  module Adapters
    class YahooMessageParser
      def initialize(uid, mail, mailbox)
        @uid     = uid
        @mail    = mail
        @mailbox = mailbox
      end

      def to_h
        {
          id:      @uid,
          provider: "yahoo",
          subject: ImapBodyParser.decode_header(@mail.subject) || "(No Subject)",
          from:    Array(@mail.from).join(", ").presence || "Unknown",
          to:      Array(@mail.to).join(", ").presence   || "Unknown",
          date:    @mail.date&.to_s || "Unknown",
          snippet: @mail.body&.decoded.to_s[0, 200],
          labels:  [ @mailbox ]
        }
      end
    end
  end
end
