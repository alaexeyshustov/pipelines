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

      # The first decoded text/html part that is not an attachment, or nil when the message has none.
      def html
        part = text_parts(@mail, "text/html").first
        part ? decode_part(part) : nil
      end

      private

      # text/plain parts joined; else the text/html parts stripped to text. Attachments and non-text parts (a PDF,
      # an image) are never read, at any nesting depth.
      def extract_body(mail)
        plain = text_parts(mail, "text/plain")
        return plain.map { |part| decode_part(part) }.join("\n\n") unless plain.empty?

        html = text_parts(mail, "text/html")
        html.map { |part| HtmlText.to_text(decode_part(part)) }.join("\n\n")
      end

      # Leaf parts of +mime_type+ that are not attachments; the message itself counts when it is not multipart.
      def text_parts(mail, mime_type)
        return mail.parts.reject(&:attachment?).flat_map { |part| text_parts(part, mime_type) } if mail.multipart?

        leaf_type = mail.mime_type || "text/plain" # : String
        leaf_type == mime_type ? [ mail ] : []
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
