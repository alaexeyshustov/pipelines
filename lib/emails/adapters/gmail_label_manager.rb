require "google/apis/gmail_v1"

module Emails
  module Adapters
    class GmailLabelManager
      def initialize(service:, labels_provider:)
        @service = service
        @labels_provider = labels_provider
      end

      def modify_labels(message_id, add: [], remove: [], source_mailbox: nil)
        _source_mailbox = source_mailbox
        request = Google::Apis::GmailV1::ModifyMessageRequest.new(
          add_label_ids: add,
          remove_label_ids: remove
        )
        message = @service.modify_message("me", message_id, request)
        raise "Message not found: #{message_id}" unless message

        { id: message.id || message_id, labels: Array(message.label_ids) }
      rescue Google::Apis::ClientError => error
        raise error unless error.message.include?("Label name exists or conflicts")

        { id: message_id, labels: [] }
      end

      def create_label(name:)
        label  = Google::Apis::GmailV1::Label.new(name: name)
        result = @service.create_user_label("me", label)
        validate_label_result!(result, name)
      rescue Google::Apis::ClientError => error
        raise error unless error.message.include?("Label name exists or conflicts")
        find_existing_label(name)
      end

      def build_label_ids(label_ids)
        # steep:ignore:start
        id_map = @labels_provider.call.each_with_object({}) do |lbl, map|
          id, name = lbl.values_at(:id, :name)
          map[id] = id
          map[name] = id
        end
        # steep:ignore:end
        Array.wrap(label_ids).filter_map { |label| id_map[label] }
      end

      private

      def validate_label_result!(result, name)
        raise "Label create error: #{name}" unless result

        id = result.id
        result_name = result.name
        type = result.type
        raise "Label create error: #{name}" unless id && result_name && type

        { id: id, name: result_name, type: type }
      end

      def find_existing_label(name)
        found = @labels_provider.call.find { |lbl| lbl[:name] == name } ||
                raise("Failed to create or find existing label '#{name}'")
        { id: found[:id], name: found[:name], type: found[:type] }
      end
    end
  end
end
