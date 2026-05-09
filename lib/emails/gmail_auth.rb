require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "socket"
require "cgi"

module Emails
  class GmailAuth
  USER_ID = "default"

  def initialize(credentials_path:, token_path:, scope:, output: $stderr)
    @credentials_path = credentials_path
    @token_path       = token_path
    @scope            = scope
    @output           = output
  end

  def credentials
    tcp_server   = TCPServer.new("localhost", 0)
    port         = tcp_server.addr[1]
    callback_uri = "http://localhost:#{port}"

    authorizer = build_authorizer(callback_uri:)
    creds      = authorizer.get_credentials(USER_ID)

    if creds.nil?
      url = authorizer.get_authorization_url(base_url: callback_uri)
      @output.puts "Opening browser for authorization..."
      @output.puts url
      system("open", url, err: File::NULL) || system("xdg-open", url, err: File::NULL)
      @output.puts "Waiting for authorization callback..."

      client       = tcp_server.accept
      request_line = client.gets
      client.print "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n"
      client.print "<html><body><h1>Authorization successful!</h1><p>You can close this tab.</p></body></html>"
      client.close
      tcp_server.close

      match = request_line&.match(/[?&]code=([^&\s]+)/)
      raise "Authorization failed: no code received in callback" unless match

      code  = CGI.unescape(match[1])
      creds = authorizer.get_and_store_credentials_from_code(
        user_id: USER_ID, code: code, base_url: callback_uri
      )
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

  def build_authorizer(callback_uri:)
    client_id   = Google::Auth::ClientId.from_file(@credentials_path)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: @token_path)
    Google::Auth::UserAuthorizer.new(client_id, @scope, token_store, callback_uri:)
  end
  end
end
