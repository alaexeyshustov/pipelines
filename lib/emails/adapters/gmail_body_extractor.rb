module Emails
  module Adapters
    class GmailBodyExtractor
      def initialize(payload)
        @payload = payload
      end

      # Plain text: text/plain parts when present, otherwise the HTML turned
      # into text by Emails::HtmlText (as ImapBodyParser does). Use #html for the raw markup.
      def body
        extract_body(@payload)
      end

      # The text/html content, or nil when the message has none.
      def html
        found = html_parts(@payload)
        found.empty? ? nil : found.join("\n\n")
      end

      private

      def html_parts(part)
        data = part.body&.data
        own = part.mime_type == "text/html" && data ? [ decode_body(data) ] : Array.new
        own + Array(part.parts).flat_map { |child| html_parts(child) }
      end

      def extract_body(payload)
        parts = payload.parts
        if parts&.any?
          extract_from_multipart(payload, parts)
        elsif (body_data = payload.body&.data) && !body_data.empty?
          decoded = decode_body(body_data)
          payload.mime_type == "text/html" ? HtmlText.to_text(decoded) : decoded
        else
          ""
        end
      end

      def extract_from_multipart(payload, parts)
        text_parts = collect_parts(payload, "text/plain")
        return text_parts.join("\n\n") unless text_parts.empty?

        html_parts = collect_parts(payload, "text/html")
        return HtmlText.to_text(html_parts.join("\n\n")) unless html_parts.empty?

        parts.filter_map { |part|
          extracted = extract_body(part)
          extracted unless extracted.empty?
        }.join("\n\n")
      end

      def collect_parts(payload, mime_type)
        parts = payload.parts
        return Array.new unless parts

        parts.flat_map { |part| collect_part(part, mime_type) }
      end

      def collect_part(part, mime_type)
        nested = collect_parts(part, mime_type)
        body_data = part.body&.data
        if part.respond_to?(:mime_type) && part.mime_type == mime_type && body_data
          [ decode_body(body_data) ] + nested
        else
          nested
        end
      end

      def decode_body(data)
        return "" if data.blank?

        data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      rescue StandardError
        ""
      end
    end
  end
end
