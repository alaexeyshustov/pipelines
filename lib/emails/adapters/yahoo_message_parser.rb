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
        fields.merge(snippet: decoded.to_s[0, 200]) # : message
      end

      # The message with its decoded text +body+. A multipart snippet is the start of that body, not of the raw MIME;
      # a single part keeps its snippet (the first 200 characters of its decoded body).
      def to_message
        body = ImapBodyParser.new(@mail).body
        snippet = @mail.multipart? ? body[0, 200] : @mail.body&.decoded.to_s[0, 200] # : String?
        fields.merge(snippet: snippet, body: body) # : message
      end

      private

      def fields
        {
          id:       @uid.to_s,
          provider: "yahoo",
          subject:  decode_subject,
          from:     format_addresses(@mail.from),
          to:       format_addresses(@mail.to),
          date:     @mail.date&.to_s || "Unknown",
          labels:   [ @mailbox ]
        }
      end

      def decode_subject
        ImapBodyParser.decode_header(@mail.subject) || "(No Subject)"
      end

      def format_addresses(addresses)
        Array(addresses).join(", ").presence || "Unknown"
      end
    end
  end
end
