module Emails
  module Adapters
    class GmailMessageParser
      def initialize(message)
        @message = message
      end

      def to_h
        headers = @message.payload.headers
        {
          id:        @message.id,
          provider:  "gmail",
          thread_id: @message.thread_id,
          subject:   header_value(headers, "Subject") || "(No Subject)",
          from:      header_value(headers, "From")    || "Unknown",
          to:        header_value(headers, "To")      || "Unknown",
          date:      header_value(headers, "Date")    || "Unknown",
          snippet:   @message.snippet,
          labels:    @message.label_ids || []
        }
      end

      private

      def header_value(headers, name)
        headers.find { |header| header.name == name }&.value
      end
    end
  end
end
