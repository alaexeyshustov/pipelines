module Emails
  module Adapters
    # Attachment metadata and bytes of Gmail messages.
    class GmailAttachmentReader
      def initialize(service)
        @service = service
      end

      # Raw bytes of a message attachment.
      def data(message_id, attachment_id)
        body = @service.get_user_message_attachment("me", message_id.to_s, attachment_id.to_s) # steep:ignore
        raise "Attachment not found: #{attachment_id}" unless body

        body.data.to_s
      end

      # Attachment metadata of a message: [{ id:, filename:, mime_type:, size: }], nested parts included.
      def list(message_id)
        message = @service.get_user_message("me", message_id.to_s, format: "full")
        raise "Message not found: #{message_id}" unless message

        collect(message.payload)
      end

      private

      def collect(part)
        own = metadata(part)
        own + Array(part.parts).flat_map { |child| collect(child) }
      end

      def metadata(part)
        body = part.body
        filename = part.filename.to_s # steep:ignore
        return [] unless body&.attachment_id && !filename.empty?

        [ { id: body.attachment_id.to_s, filename: filename, mime_type: part.mime_type.to_s, size: body.size.to_i } ]
      end
    end
  end
end
