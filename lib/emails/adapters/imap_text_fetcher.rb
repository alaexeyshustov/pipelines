module Emails
  module Adapters
    # Reads a message over IMAP without downloading it whole (GH #304): BODYSTRUCTURE and the header first, then only
    # the text/plain and text/html parts, each cut at MAX_TEXT_PART_BYTES. Attachments and RFC822 are never fetched.
    # The result is a reduced Mail with the original headers and the (still encoded) text parts, so Mail decodes
    # transfer encodings and charsets as for a whole message.
    class ImapTextFetcher
      MAX_TEXT_PART_BYTES = 1_048_576
      MAX_TEXT_PARTS = 20
      CONTENT_HEADERS = /^Content-(?:Type|Transfer-Encoding):[^\r\n]*(?:\r?\n[ \t][^\r\n]*)*\r?\n/i
      SAFE_CHARSET = /\A[\w.:-]+\z/

      def initialize(session)
        @session = session
      end

      # The message of +uid+ in +mailbox+, or nil when the UID does not exist. Takes the session lock once.
      def mail(uid, mailbox:)
        @session.with_lock do
          @session.ensure_mailbox(mailbox)
          head = @session.fetch(uid, %w[UID BODYSTRUCTURE BODY.PEEK[HEADER]])
          head && build(uid, head)
        end
      end

      private

      def build(uid, head)
        structure = head.bodystructure
        header = head.header.to_s.b
        leaves = text_leaves(structure)
        return Mail.new(header) if leaves.empty?

        bodies = fetch_bodies(uid, leaves)
        structure&.multipart? ? multipart(header, leaves, bodies) : Mail.new(header + bodies.fetch(0))
      end

      # A single-part message is its own body whatever its name (as ImapBodyParser#text_parts has it); in a multipart one
      # a named or located text part is an attachment.
      def text_leaves(structure)
        leaves = ImapBodyStructure.leaves(structure)
        leaves = structure&.multipart? ? leaves.select(&:text?) : leaves.select { |leaf| ImapBodyStructure::TEXT_TYPES.include?(leaf.mime_type) }
        leaves.first(MAX_TEXT_PARTS)
      end

      # The encoded bytes of each leaf, in order, from one request (a partial range cuts a part at the limit).
      def fetch_bodies(uid, leaves)
        data = @session.fetch(uid, leaves.map { |leaf| "BODY.PEEK[#{leaf.path}]<0.#{MAX_TEXT_PART_BYTES}>" })
        leaves.map do |leaf|
          numbers = leaf.part_numbers
          first = numbers.fetch(0)
          rest = numbers.drop(1)
          (data&.part(first, *rest, offset: 0) || data&.part(first, *rest)).to_s.b
        end
      end

      # The original headers with a flat multipart/mixed of the text leaves as the body.
      def multipart(header, leaves, bodies)
        boundary = "imap-text-#{SecureRandom.hex(8)}"
        parts = leaves.zip(bodies).map { |leaf, body| text_part(boundary, leaf, body.to_s) }
        Mail.new(without_content_headers(header) + multipart_header(boundary) + parts.join + "--#{boundary}--\r\n".b)
      end

      def text_part(boundary, leaf, body)
        "--#{boundary}\r\n#{part_headers(leaf)}\r\n\r\n".b + body + "\r\n".b
      end

      def multipart_header(boundary)
        %(Content-Type: multipart/mixed; boundary="#{boundary}"\r\n\r\n).b
      end

      def without_content_headers(header)
        header.gsub(CONTENT_HEADERS, "").sub(/(?:\r?\n)+\z/, "\r\n")
      end

      def part_headers(leaf)
        charset = leaf.charset
        type = charset&.match?(SAFE_CHARSET) ? "#{leaf.mime_type}; charset=#{charset}" : leaf.mime_type
        "Content-Type: #{type}\r\nContent-Transfer-Encoding: #{leaf.encoding}"
      end
    end
  end
end
