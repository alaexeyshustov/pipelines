require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"

module Emails
  module Adapters
    class GmailAdapter < BaseAdapter
      APPLICATION_NAME = "Application Pipeline"
      SCOPE = [ "https://www.googleapis.com/auth/gmail.modify" ].freeze

      def self.setup(**_opts)
        # TODO: add steps for gmail UI
        from_env(**_opts).authorize
      end

      def self.test_connection(**_opts)
        adapter = from_env(**_opts)
        adapter.on_init
        adapter.instance_variable_get(:@service).get_user_profile("me")
        puts "✓ Gmail connection successful"
      rescue StandardError => e
        puts "ERROR: Gmail connection failed - #{e.message}"
      end

      def self.reset(**_opts)
        token_path = Rails.root.join("token.yaml").to_s
        if File.exist?(token_path)
          File.delete(token_path)
          puts "✓ Token deleted: #{token_path}"
        else
          puts "✓ No token found at #{token_path} (already clean)"
        end
      end

      def self.from_env(credentials_path: nil, token_path: nil)
        credentials_path = credentials_path || ENV.fetch("GMAIL_CREDENTIALS_PATH", Rails.root.join("credentials.json").to_s)
        token_path       = token_path       || ENV.fetch("GMAIL_TOKEN_PATH", Rails.root.join("token.yaml").to_s)
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

      def list_messages(max_results: 100, query: nil, after_date: nil, before_date: nil, offset: 0, label_ids: nil, label: nil, mailbox: nil)
        label_ids ||= Array(label) if label
        date_filters = []
        date_filters << "after:#{after_date.strftime('%Y/%m/%d')}"  if after_date
        date_filters << "before:#{before_date.strftime('%Y/%m/%d')}" if before_date

        combined_query = [ query, *date_filters ].compact.join(" ").strip
        combined_query = nil if combined_query.empty?

        page_token = nil
        skipped    = 0

        while skipped < offset
          remaining = offset - skipped
          page_size = [ remaining, 500 ].min
          result    = @service.list_user_messages("me", max_results: page_size, q: combined_query,
                                                  label_ids: label_ids, page_token: page_token)
          fetched   = (result.messages || []).size
          skipped  += fetched
          page_token = result.next_page_token
          break if page_token.nil? || fetched < page_size
        end

        result   = @service.list_user_messages("me", max_results: max_results, q: combined_query,
                                              label_ids: label_ids, page_token: page_token)
        messages = result.messages || []
        messages.map { |msg| list_message(msg.id) }
      end

      def get_message(message_id, mailbox: nil)
        message = @service.get_user_message("me", message_id, format: "full")
        parse_message(message).merge(body: extract_body(message.payload))
      rescue Google::Apis::ClientError => e
        puts "ERROR: Failed to get message #{message_id} - #{e.message}"

        { id: message_id, error: e.message }
      end

      def search_messages(query, max_results: 10, mailbox: nil)
        list_messages(max_results: max_results, query: query)
      end

      def get_labels
        @labels ||= @service.list_user_labels("me").labels.map do |label|
          { id: label.id, name: label.name, type: label.type }
        end
      end

      def get_unread_count
        @service.get_user_label("me", "UNREAD").messages_total || 0
      end

      def modify_labels(message_id, add: [], remove: [], mailbox: nil)
        request = Google::Apis::GmailV1::ModifyMessageRequest.new(
          add_label_ids: add,
          remove_label_ids: remove
        )
        message = @service.modify_message("me", message_id, request)
        { id: message.id, labels: message.label_ids || [] }
      rescue Google::Apis::ClientError => e
        raise e unless e.message.include?("Label name exists or conflicts")

        { id: message_id, labels: [] }
      end

      def create_label(name:, **_opts)
        label = Google::Apis::GmailV1::Label.new(name: name)
        result = @service.create_user_label("me", label)
        { id: result.id, name: result.name, type: result.type }
      rescue Google::Apis::ClientError => e
        raise e unless e.message.include?("Label name exists or conflicts")

        existing = get_labels.find { |l| l[:name] == name } || raise("Failed to create or find existing label '#{name}'")
        { id: existing[:id], name: existing[:name], type: existing[:type] }
      end

      private

      def list_message(message_id)
        message = @service.get_user_message("me", message_id, format: "metadata",
                                            metadata_headers: %w[Subject From To Date])
        parse_message(message)
      end

      def parse_message(message)
        headers = message.payload.headers
        {
          id:        message.id,
          thread_id: message.thread_id,
          subject:   header_value(headers, "Subject") || "(No Subject)",
          from:      header_value(headers, "From")    || "Unknown",
          to:        header_value(headers, "To")      || "Unknown",
          date:      header_value(headers, "Date")    || "Unknown",
          snippet:   message.snippet,
          labels:    message.label_ids || []
        }
      end

      def header_value(headers, name)
        headers.find { |h| h.name == name }&.value
      end

      def extract_body(payload)
        if payload.parts&.any?
          text_parts = collect_parts(payload, "text/plain")
          return text_parts.join("\n\n") unless text_parts.empty?

          html_parts = collect_parts(payload, "text/html")
          return html_parts.join("\n\n") unless html_parts.empty?

          payload.parts.filter_map { |part|
            body = extract_body(part)
            body unless body.empty?
          }.join("\n\n")
        elsif payload.body&.data && !payload.body.data.empty?
          decode_body(payload.body.data)
        else
          ""
        end
      end

      def collect_parts(payload, mime_type)
        return [] unless payload.parts

        payload.parts.flat_map do |part|
          results = []
          if part.respond_to?(:mime_type) && part.mime_type == mime_type && part.body&.data
            results << decode_body(part.body.data)
          end
          results + collect_parts(part, mime_type)
        end
      end

      def decode_body(data)
        return "" if data.nil? || data.empty?

        data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      rescue StandardError
        ""
      end
    end
  end
end
