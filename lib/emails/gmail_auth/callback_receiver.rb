module Emails
  class GmailAuth
    # Receives the OAuth redirect on the CLI's loopback socket and returns the authorization code. Closes the
    # browser connection (not the server) and rejects a callback whose state is not the one this run sent.
    class CallbackReceiver
      MAX_REQUEST_LINE = 8192

      def initialize(server:, state:, timeout:)
        @server  = server
        @state   = state
        @timeout = timeout
      end

      def code
        raise CallbackTimeout, "No authorization callback received within #{@timeout} seconds" unless @server.wait_readable(@timeout)

        client = @server.accept
        raise CallbackTimeout, "No authorization request received within #{@timeout} seconds" unless client.wait_readable(@timeout)

        reply_to(client)
      ensure
        client&.close
      end

      private

      def reply_to(client)
        code = code_from(client.gets(MAX_REQUEST_LINE))
        respond(client, "Authorization successful!", "You can close this tab.")
        code
      rescue StandardError
        respond(client, "Authorization failed", "Return to the terminal and try again.")
        raise
      end

      def code_from(request_line)
        returned_state = param(request_line, "state")
        unless returned_state && ActiveSupport::SecurityUtils.secure_compare(returned_state, @state)
          raise InvalidState, "Authorization callback state does not match"
        end

        code = param(request_line, "code")
        raise MissingCode, "Authorization failed: no code received in callback" if code.blank?

        code
      end

      def param(request_line, name)
        raw = request_line&.match(/[?&]#{name}=([^&\s]+)/)&.[](1)
        raw && CGI.unescape(raw)
      end

      def respond(client, heading, message)
        client.print "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n"
        client.print "<html><body><h1>#{heading}</h1><p>#{message}</p></body></html>"
      end
    end
  end
end
