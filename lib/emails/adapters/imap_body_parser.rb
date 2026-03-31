module Emails
  module Adapters
    class ImapBodyParser
      def self.decode_header(value)
        return nil if value.nil?

        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      rescue StandardError
        value.to_s
      end

      def initialize(mail)
        @mail = mail
      end

      def body
        extract_body(@mail)
      end

      private

      def extract_body(mail)
        if mail.multipart?
          parts = mail.parts
          plain = parts.find { |part| part.mime_type == "text/plain" }
          return decode_part(plain) if plain

          html = parts.find { |part| part.mime_type == "text/html" }
          return strip_html(decode_part(html)) if html

          parts.filter_map { |part| extract_body(part) }.reject(&:empty?).join("\n\n")
        elsif mail.mime_type == "text/html"
          strip_html(decode_part(mail))
        else
          decode_part(mail)
        end
      end

      def decode_part(part)
        return "" unless part

        body = part.respond_to?(:decoded) ? part.decoded : part.body.decoded
        body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip
      rescue StandardError
        ""
      end

      def strip_html(html)
        html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end
    end
  end
end
