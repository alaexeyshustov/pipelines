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

      # The decoded text/html part, or nil when the message has none.
      def html
        part = find_html(@mail)
        part ? decode_part(part) : nil
      end

      private

      def find_html(mail)
        return mail if mail.mime_type == "text/html"
        return nil unless mail.multipart?

        mail.parts.each do |part|
          found = find_html(part)
          return found if found
        end
        nil
      end

      def extract_body(mail)
        if mail.multipart?
          extract_multipart_body(mail)
        else
          mail_mime = mail.mime_type # : String?
          mail_mime == "text/html" ? HtmlText.to_text(decode_part(mail)) : decode_part(mail)
        end
      end

      def extract_multipart_body(mail)
        parts = mail.parts # : Array[Mail::Part]
        plain = parts.find { |part| part.mime_type == "text/plain" } # : Mail::Part?
        return decode_part(plain) if plain

        html = parts.find { |part| part.mime_type == "text/html" } # : Mail::Part?
        return HtmlText.to_text(decode_part(html)) if html

        parts.filter_map { |part| extract_body(part) }.reject(&:empty?).join("\n\n")
      end

      def decode_part(part)
        return "" unless part

        body = if part.respond_to?(:decoded)
          part.decoded
        else
          body_obj = part.body # : Mail::Body
          body_obj.decoded
        end # : String
        body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip
      rescue StandardError
        ""
      end
    end
  end
end
