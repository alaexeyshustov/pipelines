require "google/apis/gmail_v1"

module Emails
  module Adapters
    class GmailAdapter < BaseAdapter
      def self.setup(opts = {})
        GmailSession.setup(opts)
      end

      def self.test_connection(opts = {})
        GmailSession.test_connection(opts)
      end

      def self.reset
        GmailSession.reset
      end

      def self.from_env(opts = {})
        GmailSession.from_env(opts)
      end

      def initialize(credentials_path:, token_path:)
        @session = GmailSession.new(credentials_path: credentials_path, token_path: token_path)
        @service = Google::Apis::GmailV1::GmailService.new
        @service.client_options.application_name = GmailSession::APPLICATION_NAME
        @label_manager = GmailLabelManager.new(service: @service, labels_provider: -> { get_labels })
      end

      def on_init
        @service.authorization = authorize
      end

      def authorize
        @session.authorize
      end

      def search_messages(query, max_results: 100, offset: 0, label: nil)
        label_ids = label ? @label_manager.build_label_ids(label) : nil
        fetch_messages(max_results, offset) do |page_size, page_token|
          @service.list_user_messages("me", max_results: page_size, q: query, page_token:, label_ids:)
        end
      end

      def list_messages(max_results: 100, after_date: nil, before_date: nil, offset: 0, label: nil)
        label_ids    = label ? @label_manager.build_label_ids(label) : nil
        date_filters = [
          ("after:#{after_date.strftime('%Y/%m/%d')}"   if after_date),
          ("before:#{before_date.strftime('%Y/%m/%d')}" if before_date)
        ].compact
        query = date_filters.empty? ? nil : date_filters.join(" ")
        fetch_messages(max_results, offset) do |page_size, page_token|
          @service.list_user_messages("me", max_results: page_size, q: query, label_ids:, page_token:)
        end
      end

      def get_message(message_id, **_kwargs)
        message = @service.get_user_message("me", message_id.to_s, format: "full")
        raise "Message not found: #{message_id}" unless message

        format_message(message, GmailMessageParser.new(message).to_h)
      end

      def get_unread_count
        label = @service.get_user_label("me", "UNREAD")
        label&.messages_total.to_i
      end

      def get_labels
        response = @service.list_user_labels("me")
        @labels ||= Array(response&.labels).filter_map do |label|
          id = label.id
          name = label.name
          type = label.type
          next unless id && name && type

          { id: id, name: name, type: type }
        end
      end

      def modify_labels(message_id, add: [], remove: [], source_mailbox: nil)
        @label_manager.modify_labels(message_id, add: add, remove: remove, source_mailbox: source_mailbox)
      end

      def create_label(name:)
        @label_manager.create_label(name: name)
      end

      private

      def format_message(message, parsed)
        {
          id: parsed[:id],
          provider: parsed[:provider],
          subject: parsed[:subject],
          from: parsed[:from],
          to: parsed[:to],
          date: parsed[:date],
          snippet: parsed[:snippet],
          body: GmailBodyExtractor.new(message.payload).body,
          thread_id: parsed[:thread_id],
          labels: parsed[:labels]
        }
      end

      def fetch_messages(max_results, offset, &block)
        GmailPaginator.new(max_results, offset, &block).messages.filter_map { |msg| list_message(msg.id.to_s) }
      end

      def list_message(message_id)
        metadata_headers = %w[From To Subject Date]
        @service.get_user_message("me", message_id, format: "metadata", metadata_headers:)
          &.then { |msg| GmailMessageParser.new(msg).to_h }
      end
    end
  end
end
