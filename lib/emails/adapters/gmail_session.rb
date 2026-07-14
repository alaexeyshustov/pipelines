require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"

module Emails
  module Adapters
    class GmailSession
      APPLICATION_NAME = "Application Pipeline"
      SCOPE = [ "https://www.googleapis.com/auth/gmail.modify" ].freeze

      def self.setup(opts = {})
        Rails.logger.debug { <<~INSTRUCTIONS }
          Gmail setup:
          1. Create a project in Google Cloud Console.
          2. Enable the Gmail API for your project.
          3. Create OAuth 2.0 credentials and download the JSON file.
          4. Save the file as credentials.json in the project root.

          Clearing any existing token and launching OAuth authorization flow...
        INSTRUCTIONS
        from_env(opts).authorize
        Rails.logger.debug "✓ Gmail OAuth token saved."
      end

      def self.test_connection(opts = {})
        adapter = from_env(opts)
        adapter.on_init
        adapter.instance_variable_get(:@service).get_user_profile("me")
        # rubocop:disable Rails/Output
        puts "✓ Gmail connection successful"
        # rubocop:enable Rails/Output
      rescue StandardError => error
        # rubocop:disable Rails/Output
        puts "ERROR: Gmail connection failed - #{error.message}"
        # rubocop:enable Rails/Output
      end

      def self.reset
        token_path = Rails.root.join("token.yaml").to_s
        if File.exist?(token_path)
          File.delete(token_path)
          Rails.logger.debug { "✓ Token deleted: #{token_path}" }
        else
          Rails.logger.debug { "✓ No token found at #{token_path} (already clean)" }
        end
      end

      def self.from_env(opts = {})
        root             = Rails.root
        credentials_path = opts[:credentials_path] || ENV.fetch("GMAIL_CREDENTIALS_PATH", root.join("credentials.json").to_s)
        token_path       = opts[:token_path]       || ENV.fetch("GMAIL_TOKEN_PATH", root.join("token.yaml").to_s)
        unless File.exist?(credentials_path)
          raise "Missing Gmail credentials file. Please create #{credentials_path} with your Google API credentials."
        end
        adapter = GmailAdapter.new(credentials_path: credentials_path, token_path: token_path)
        adapter.on_init
        adapter
      end

      def initialize(credentials_path:, token_path:)
        @credentials_path = credentials_path
        @token_path       = token_path
      end

      def authorize
        GmailAuth.new(
          credentials_path: @credentials_path,
          token_path:       @token_path,
          scope:            SCOPE
        ).credentials
      end
    end
  end
end
