module Emails
  module Adapters
    class GmailBodyExtractor
      def initialize(payload)
        @payload = payload
      end

      def body
        extract_body(@payload)
      end

      private

      def extract_body(payload)
        parts = payload.parts
        if parts&.any?
          text_parts = collect_parts(payload, "text/plain")
          return text_parts.join("\n\n") unless text_parts.empty?

          html_parts = collect_parts(payload, "text/html")
          return html_parts.join("\n\n") unless html_parts.empty?

          parts.filter_map { |part|
            extracted = extract_body(part)
            extracted unless extracted.empty?
          }.join("\n\n")
        elsif (body_data = payload.body&.data) && !body_data.empty?
          decode_body(body_data)
        else
          ""
        end
      end

      def collect_parts(payload, mime_type)
        parts = payload.parts
        return [] unless parts

        parts.flat_map do |part|
          results = []
          if part.respond_to?(:mime_type) && part.mime_type == mime_type && (body_data = part.body&.data)
            results << decode_body(body_data)
          end
          results + collect_parts(part, mime_type)
        end
      end

      def decode_body(data)
        return "" if data.nil? || data.empty?

        data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      rescue StandardError
        ""
      end
    end
  end
end
