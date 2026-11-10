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
        own = part.mime_type == "text/html" && data ? [ decode_body(data, part) ] : Array.new
        own + Array(part.parts).flat_map { |child| html_parts(child) }
      end

      def extract_body(payload)
        parts = payload.parts
        if parts&.any?
          extract_from_multipart(payload, parts)
        elsif (body_data = payload.body&.data) && !body_data.empty?
          decoded = decode_body(body_data, payload)
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
          [ decode_body(body_data, part) ] + nested
        else
          nested
        end
      end

      # Gmail hands the body over as raw bytes (ASCII-8BIT): label them with the charset of the part's Content-Type
      # header (UTF-8 when absent or unknown), then transcode to UTF-8 and scrub what is still invalid.
      def decode_body(data, part)
        return "" if data.blank?

        text = data.dup.force_encoding(charset_of(part))
        text = text.encode("UTF-8", invalid: :replace, undef: :replace) unless text.encoding == Encoding::UTF_8
        text.scrub
      rescue StandardError
        ""
      end

      def charset_of(part)
        header = Array(part.headers).find { |candidate| candidate.name.to_s.casecmp?("Content-Type") }
        name = header&.value.to_s[/charset\s*=\s*"?([^";\s]+)/i, 1]
        (name && Encoding.find(name)) || Encoding::UTF_8
      rescue ArgumentError
        Encoding::UTF_8
      end
    end
  end
end
