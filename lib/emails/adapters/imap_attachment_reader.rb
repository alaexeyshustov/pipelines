module Emails
  module Adapters
    # Attachment metadata and bytes of IMAP (Yahoo) INBOX messages, fetched part by part (GH #304): the structure
    # lists them, only the requested part's bytes are downloaded. Attachments inside a message/rfc822 part are not listed.
    class ImapAttachmentReader
      PART_PATH = /\A\d+(?:\.\d+)*\z/

      def initialize(session)
        @session = session
      end

      # Attachment metadata of a message: [{ id: "<part path>", filename:, mime_type:, size: }] (size is the encoded
      # octet count). Inline parts (signature logos) are left out, as for Gmail.
      def list(message_id)
        validity, uid = ImapInboxReader.split_message_id(message_id)
        @session.with_lock do
          attachment_leaves(message_id, validity, uid).map do |leaf|
            { id: leaf.path, filename: leaf.filename.to_s, mime_type: leaf.mime_type, size: leaf.size }
          end
        end
      end

      # Decoded bytes of one attachment part. +attachment_id+ must be a listed attachment's part path.
      def data(message_id, attachment_id)
        validity, uid = ImapInboxReader.split_message_id(message_id)
        raise "Attachment not found: #{attachment_id}" unless attachment_id.match?(PART_PATH)

        @session.with_lock do
          leaf = attachment_leaves(message_id, validity, uid).find { |candidate| candidate.path == attachment_id }
          raise "Attachment not found: #{attachment_id}" unless leaf

          decode(leaf, fetch_part(uid, leaf))
        end
      end

      private

      # Must run inside the session lock. The UIDVALIDITY check comes first, so a reset mailbox never hands over
      # another message's files.
      def attachment_leaves(message_id, validity, uid)
        @session.ensure_mailbox(ImapInboxReader::MAILBOX)
        raise "UIDVALIDITY changed for message #{message_id}" if validity && @session.uid_validity(ImapInboxReader::MAILBOX) != validity

        structure = @session.fetch(uid, %w[UID BODYSTRUCTURE])&.then { |fetched| fetched.bodystructure } || raise("Message not found: #{message_id}")
        ImapBodyStructure.leaves(structure).select(&:attachment?)
      end

      def fetch_part(uid, leaf)
        numbers = leaf.part_numbers
        @session.fetch(uid, [ "BODY.PEEK[#{leaf.path}]" ])&.part(numbers.fetch(0), *numbers.drop(1)) || raise("Attachment not found: #{leaf.path}")
      end

      def decode(leaf, encoded)
        Mail::Encodings.get_encoding(leaf.encoding).decode(encoded) # : String
      end
    end
  end
end
