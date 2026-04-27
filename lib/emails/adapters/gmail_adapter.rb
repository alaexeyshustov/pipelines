require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"

module Emails
  module Adapters
    class GmailAdapter < BaseAdapter
      APPLICATION_NAME = "Application Pipeline"
      SCOPE = [ "https://www.googleapis.com/auth/gmail.modify" ].freeze

      def self.setup(**kwargs)
        puts <<~INSTRUCTIONS
          Gmail setup:
          1. Create a project in Google Cloud Console.
          2. Enable the Gmail API for your project.
          3. Create OAuth 2.0 credentials and download the JSON file.
          4. Save the file as credentials.json in the project root.

          Clearing any existing token and launching OAuth authorization flow...
        INSTRUCTIONS
        from_env(**kwargs).authorize
        puts "✓ Gmail OAuth token saved."
      end

      def self.test_connection(**kwargs)
        adapter = from_env(**kwargs)
        adapter.on_init
        adapter.instance_variable_get(:@service).get_user_profile("me")
        puts "✓ Gmail connection successful"
      rescue StandardError => error
        puts "ERROR: Gmail connection failed - #{error.message}"
      end

      def self.reset
        token_path = Rails.root.join("token.yaml").to_s
        if File.exist?(token_path)
          File.delete(token_path)
          puts "✓ Token deleted: #{token_path}"
        else
          puts "✓ No token found at #{token_path} (already clean)"
        end
      end

      def self.from_env(credentials_path: nil, token_path: nil)
        root             = Rails.root
        credentials_path = credentials_path || ENV.fetch("GMAIL_CREDENTIALS_PATH", root.join("credentials.json").to_s)
        token_path       = token_path       || ENV.fetch("GMAIL_TOKEN_PATH", root.join("token.yaml").to_s)
        unless File.exist?(credentials_path)
          raise   "Missing Gmail credentials file. Please create #{credentials_path} with your Google API credentials."
        end
        adapter = new(credentials_path: credentials_path, token_path: token_path)
        adapter.on_init
        adapter
      end

      def initialize(credentials_path:, token_path:)
        @credentials_path = credentials_path
        @token_path       = token_path
        @service = Google::Apis::GmailV1::GmailService.new
        @service.client_options.application_name = APPLICATION_NAME
      end

      def on_init
        @service.authorization = authorize
      end

      def authorize
        GmailAuth.new(
          credentials_path: @credentials_path,
          token_path:       @token_path,
          scope:            SCOPE
        ).credentials
      end

      def search_messages(query, max_results: 100, offset: 0, label: nil)
        label_ids = label ? build_label_ids(label) : nil
        fetch_messages(max_results, offset) do |page_size, page_token|
          @service.list_user_messages("me", max_results: page_size, q: query, page_token:, label_ids:)
        end
      end

      def list_messages(max_results: 100, after_date: nil, before_date: nil, offset: 0, label: nil)
        label_ids    = label ? build_label_ids(label) : nil
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
        return { id: message_id, error: "Message not found" } unless message

        GmailMessageParser.new(message).to_h.merge(body: GmailBodyExtractor.new(message.payload).body)
      rescue Google::Apis::ClientError => error
        msg = error.message
        puts "ERROR: Failed to get message #{message_id} - #{msg}"
        { id: message_id, error: msg }
      end

      def get_unread_count
        @service.get_user_label("me", "UNREAD").messages_total.to_i || 0
      end

      def get_labels
        @labels ||= @service.list_user_labels("me").labels.map do |label|
          { id: label.id, name: label.name, type: label.type }
        end
      end

      def modify_labels(message_id, add: [], remove: [], source_mailbox: nil)
        _source_mailbox = source_mailbox
        request = Google::Apis::GmailV1::ModifyMessageRequest.new(
          add_label_ids: add,
          remove_label_ids: remove
        )
        message = @service.modify_message("me", message_id, request)
        return { id: message_id, error: "Message not found" } unless message

        { id: message.id, labels: message.label_ids || [] }
      rescue Google::Apis::ClientError => error
        raise error unless error.message.include?("Label name exists or conflicts")

        # steep:ignore:start
        { id: message_id, labels: [] }
        # steep:ignore:end
      end

      def create_label(name:)
        label  = Google::Apis::GmailV1::Label.new(name: name)
        result = @service.create_user_label("me", label)
        return { name: name, error: "Label create error" } unless result

        { id: result.id, name: result.name, type: result.type }
      rescue Google::Apis::ClientError => error
        raise error unless error.message.include?("Label name exists or conflicts")
        find_existing_label(name)
      end

      private

      def fetch_messages(max_results, offset, &block)
        GmailPaginator.new(max_results, offset, &block).messages.map { |msg| list_message(msg.id.to_s) }.compact
      end

      def find_existing_label(name)
        found = get_labels.find { |lbl| lbl[:name] == name } ||
                raise("Failed to create or find existing label '#{name}'")
        found.slice(:id, :name, :type)
      end

      def build_label_ids(label_ids)
        # steep:ignore:start
        id_map = get_labels.each_with_object({}) do |lbl, map|
          id, name = lbl.values_at(:id, :name)
          map.merge!(id => id, name => id)
        end
        # steep:ignore:end
        Array.wrap(label_ids).filter_map { |label| id_map[label] }
      end

      def list_message(message_id)
        metadata_headers = %w[From To Subject Date]
        @service.get_user_message("me", message_id, format: "metadata", metadata_headers:)
          &.then { |msg| GmailMessageParser.new(msg).to_h }
      end
    end
  end
end
