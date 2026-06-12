module Emails
  module Adapters
    class YahooMessageParser
      def initialize(uid, mail, mailbox)
        @uid     = uid
        @mail    = mail
        @mailbox = mailbox
      end

      def to_h
        raw_date = @mail.date    # : DateTime?
        raw_body = @mail.body    # : Mail::Body?
        decoded  = raw_body&.decoded # : String?
        {
          id:      @uid.to_s,
          provider: "yahoo",
          subject: ImapBodyParser.decode_header(@mail.subject) || "(No Subject)",
          from:    Array(@mail.from).join(", ").presence || "Unknown",
          to:      Array(@mail.to).join(", ").presence   || "Unknown",
          date:    raw_date&.to_s || "Unknown",
          snippet: decoded.to_s[0, 200],
          labels:  [ @mailbox ]
        }
      end
    end
  end
end
