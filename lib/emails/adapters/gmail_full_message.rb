module Emails
  module Adapters
    # A Gmail message with everything an +Email+ row needs: plain-text and html bodies, a link to open it in the
    # web client and a parsed +Date+ (the Date header, else Gmail's +internalDate+).
    class GmailFullMessage
      WEB_URL = "https://mail.google.com/mail/u/0/#inbox/".freeze

      def initialize(message)
        @message = message
        @parsed = GmailMessageParser.new(message).to_h
        @extractor = GmailBodyExtractor.new(message.payload)
      end

      def to_h
        {
          id: @parsed[:id].to_s, provider: "gmail", subject: @parsed[:subject], from: @parsed[:from], to: @parsed[:to],
          date: date, body: @extractor.body, html_body: @extractor.html, source_url: "#{WEB_URL}#{@parsed[:id]}",
          thread_id: @parsed[:thread_id], labels: @parsed[:labels]
        }
      end

      private

      def date
        header = @parsed[:date]
        Time.rfc2822(header).utc
      rescue ArgumentError
        internal_date = @message.internal_date
        raise ArgumentError, "Message #{@parsed[:id]} has no usable date" unless internal_date

        Time.at(internal_date.to_i / 1000).utc
      end
    end
  end
end
