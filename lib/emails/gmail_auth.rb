require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "socket"
require "cgi"
require "securerandom"

module Emails
  class GmailAuth
    class InteractiveAuthorizationRequired < StandardError; end
    class CallbackTimeout < StandardError; end
    class InvalidState < StandardError; end
    class MissingCode < StandardError; end

    USER_ID = "default".freeze
    ACCEPT_TIMEOUT = 120

    def initialize(credentials_path:, token_path:, scope:, output: $stderr, accept_timeout: ACCEPT_TIMEOUT)
      @credentials_path = credentials_path
      @token_path       = token_path
      @scope            = scope
      @output           = output
      @accept_timeout   = accept_timeout
    end

    # The stored credentials. With none stored this raises Emails::NotConfigured, so jobs and web requests never
    # block on a browser flow. Only the CLI setup path passes interactive: true, which opens the browser and waits
    # for the OAuth callback on a local socket.
    def credentials(interactive: false)
      return stored_credentials unless interactive

      interactive_credentials
    end

    def authorization_url(callback_uri:, state:)
      build_authorizer(callback_uri:).get_authorization_url(base_url: callback_uri, state:)
    end

    def exchange_code(code:, callback_uri:)
      build_authorizer(callback_uri:, writable: true).get_and_store_credentials_from_code(
        user_id: USER_ID, code:, base_url: callback_uri
      )
    end

    private

    def stored_credentials
      # The callback URI is only used by the authorization flow, which this path never starts.
      build_authorizer(callback_uri: "http://localhost").get_credentials(USER_ID) ||
        raise(Emails::NotConfigured, "No stored Google token at #{@token_path}: run `bin/pipeline setup` to authorize")
    end

    # The loopback server is closed on every path: a stored token, a finished or failed flow, or an authorizer
    # that cannot be built.
    def interactive_credentials
      tcp_server   = TCPServer.new("localhost", 0)
      callback_uri = "http://localhost:#{tcp_server.addr[1]}"
      authorizer   = build_authorizer(callback_uri:, writable: true)
      authorizer.get_credentials(USER_ID) || perform_interactive_auth(authorizer, tcp_server, callback_uri)
    ensure
      tcp_server&.close
    end

    def perform_interactive_auth(authorizer, tcp_server, callback_uri)
      state = SecureRandom.urlsafe_base64(32)
      url   = authorizer.get_authorization_url(base_url: callback_uri, state:)
      announce("Opening browser for authorization...", url)

      require_interactive_auth!(url)
      open_authorization_url(url)
      announce("Waiting for authorization callback...")
      code = CallbackReceiver.new(server: tcp_server, state:, timeout: @accept_timeout).code
      authorizer.get_and_store_credentials_from_code(user_id: USER_ID, code:, base_url: callback_uri)
    end

    def announce(*lines)
      lines.each { |line| @output.puts line }
    end

    def require_interactive_auth!(url)
      return if interactive_authorization_allowed?

      raise InteractiveAuthorizationRequired,
            "Interactive Gmail authorization is disabled in test. Generated authorization URL: #{url}"
    end

    # The token file holds refresh tokens. FileTokenStore/PStore keeps an existing file's mode, so tighten a looser
    # one before the store touches it and, when a token is about to be written, create it owner-only.
    def secure_token_file(writable:)
      File.open(@token_path, File::CREAT | File::WRONLY, 0o600) { nil } if writable
      File.chmod(0o600, @token_path) if File.exist?(@token_path)
    end

    def build_authorizer(callback_uri:, writable: false)
      client_id = Google::Auth::ClientId.from_file(@credentials_path)
      Google::Auth::UserAuthorizer.new(client_id, @scope, token_store(writable:), callback_uri:)
    end

    def token_store(writable:)
      secure_token_file(writable:)
      Google::Auth::Stores::FileTokenStore.new(file: @token_path)
    end

    def interactive_authorization_allowed?
      !defined?(Rails) || !Rails.env.test?
    end

    def open_authorization_url(url)
      !!(system("open", url, err: File::NULL) || system("xdg-open", url, err: File::NULL))
    end
  end
end
