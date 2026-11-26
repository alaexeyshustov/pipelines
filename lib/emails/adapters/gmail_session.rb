require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"

module Emails
  module Adapters
    class GmailSession
      APPLICATION_NAME = "Application Pipeline".freeze
      SCOPE = [ "https://www.googleapis.com/auth/gmail.modify" ].freeze

      def self.setup
        Rails.logger.debug { <<~INSTRUCTIONS }
          Gmail setup:
          1. Create a project in Google Cloud Console.
          2. Enable the Gmail API for your project.
          3. Create OAuth 2.0 credentials and download the JSON file.
          4. Save the file as credentials.json in the project root.

          Clearing any existing token and launching OAuth authorization flow...
        INSTRUCTIONS
        new(**paths_from_env).authorize(interactive: true)
        Rails.logger.debug "✓ Gmail OAuth token saved."
      end

      def self.test_connection
        from_env.profile
        "✓ Gmail connection successful"
      rescue StandardError => error
        "ERROR: Gmail connection failed - #{error.message}"
      end

      def self.reset
        token_path = token_path_from_env
        if File.exist?(token_path)
          File.delete(token_path)
          Rails.logger.debug { "✓ Token deleted: #{token_path}" }
        else
          Rails.logger.debug { "✓ No token found at #{token_path} (already clean)" }
        end
      end

      # The credentials and token paths are server config (ENV), never request or row input.
      def self.from_env
        adapter = GmailAdapter.new(**paths_from_env)
        adapter.on_init
        adapter
      end

      # The OAuth flow over the configured paths; the web setup uses it for the authorization URL and code exchange.
      def self.auth_from_env
        new(**paths_from_env).auth
      end

      def self.paths_from_env
        credentials_path = ENV.fetch("GMAIL_CREDENTIALS_PATH", Rails.root.join("credentials.json").to_s)
        unless File.exist?(credentials_path)
          raise Emails::NotConfigured, "Missing Gmail credentials file. Please create #{credentials_path} with your Google API credentials."
        end

        { credentials_path:, token_path: token_path_from_env }
      end
      private_class_method :paths_from_env

      def self.token_path_from_env
        ENV.fetch("GMAIL_TOKEN_PATH", Rails.root.join("token.yaml").to_s)
      end
      private_class_method :token_path_from_env

      def initialize(credentials_path:, token_path:)
        @credentials_path = credentials_path
        @token_path       = token_path
      end

      # Stored credentials; raises Emails::NotConfigured without a token. Only the CLI setup passes interactive: true.
      def authorize(interactive: false)
        auth.credentials(interactive:)
      end

      # The OAuth flow for these paths and SCOPE; the web setup uses it for the authorization URL and code exchange.
      def auth
        GmailAuth.new(credentials_path: @credentials_path, token_path: @token_path, scope: SCOPE)
      end
    end
  end
end
