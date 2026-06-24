require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "socket"
require "cgi"

module Emails
  class GmailAuth
    class InteractiveAuthorizationRequired < StandardError; end

    USER_ID = "default"

    def initialize(credentials_path:, token_path:, scope:, output: $stderr)
      @credentials_path = credentials_path
      @token_path       = token_path
      @scope            = scope
      @output           = output
    end

    def credentials
      tcp_server, callback_uri, authorizer = setup_tcp_auth_context
      creds = authorizer.get_credentials(USER_ID)

      if creds.nil?
        creds = perform_interactive_auth(authorizer, tcp_server, callback_uri)
      else
        tcp_server.close
      end

      creds
    end

    def authorization_url(callback_uri:)
      build_authorizer(callback_uri:).get_authorization_url(base_url: callback_uri)
    end

    def exchange_code(code:, callback_uri:)
      build_authorizer(callback_uri:).get_and_store_credentials_from_code(
        user_id: USER_ID, code:, base_url: callback_uri
      )
    end

    private

    def setup_tcp_auth_context
      tcp_server   = TCPServer.new("localhost", 0)
      callback_uri = "http://localhost:#{tcp_server.addr[1]}"
      authorizer   = build_authorizer(callback_uri:)
      [ tcp_server, callback_uri, authorizer ]
    end

    def perform_interactive_auth(authorizer, tcp_server, callback_uri)
      url = authorizer.get_authorization_url(base_url: callback_uri)
      @output.puts "Opening browser for authorization..."
      @output.puts url

      require_interactive_auth!(tcp_server, url)
      open_authorization_url(url)
      @output.puts "Waiting for authorization callback..."
      code = accept_oauth_callback(tcp_server)
      authorizer.get_and_store_credentials_from_code(user_id: USER_ID, code:, base_url: callback_uri)
    end

    def require_interactive_auth!(tcp_server, url)
      return if interactive_authorization_allowed?

      tcp_server.close
      raise InteractiveAuthorizationRequired,
            "Interactive Gmail authorization is disabled in test. Generated authorization URL: #{url}"
    end

    def accept_oauth_callback(tcp_server)
      client       = tcp_server.accept
      request_line = client.gets
      client.print "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n"
      client.print "<html><body><h1>Authorization successful!</h1><p>You can close this tab.</p></body></html>"
      client.close
      tcp_server.close

      raw_code = request_line&.match(/[?&]code=([^&\s]+)/)&.[](1)
      raise "Authorization failed: no code received in callback" if raw_code.blank?

      CGI.unescape(raw_code.to_s)
    end

    def build_authorizer(callback_uri:)
      client_id   = Google::Auth::ClientId.from_file(@credentials_path)
      token_store = Google::Auth::Stores::FileTokenStore.new(file: @token_path)
      Google::Auth::UserAuthorizer.new(client_id, @scope, token_store, callback_uri:)
    end

    def interactive_authorization_allowed?
      !defined?(Rails) || !Rails.env.test?
    end

    def open_authorization_url(url)
      !!(system("open", url, err: File::NULL) || system("xdg-open", url, err: File::NULL))
    end
  end
end
