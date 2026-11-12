module Emails
  module Adapters
    # A Yahoo (IMAP) message with everything an +Email+ row needs: plain-text and html bodies and a parsed +Date+.
    # IMAP has no web link, so +source_url+ is nil. The id is "<uid_validity>:<uid>" (UIDs are only unique within
    # one UIDVALIDITY).
    class YahooFullMessage
      def initialize(uid_validity, uid, mail)
        @uid_validity = uid_validity
        @uid = uid
        @mail = mail
        @parsed = YahooMessageParser.new(uid, mail, "INBOX").to_h
        @bodies = ImapBodyParser.new(mail)
      end

      def to_h
        {
          id: "#{@uid_validity}:#{@uid}", provider: "yahoo", subject: @parsed[:subject], from: @parsed[:from],
          to: @parsed[:to], date: date, body: @bodies.body, html_body: @bodies.html, source_url: nil,
          thread_id: nil, labels: @parsed[:labels]
        }
      end

      private

      def date
        parsed = @mail.date
        raise ArgumentError, "Message #{@uid} has no usable date" unless parsed

        parsed.to_time.utc
      end
    end
  end
end
