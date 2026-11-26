module Emails
  module Adapters
    class ImapSession
      OPEN_TIMEOUT = 10

      def initialize(host:, port:, username:, password:)
        @imap_config     = { host:, port:, username:, password: }
        @mutex           = Mutex.new
        @imap            = nil
        @current_mailbox = nil
      end

      def on_exit
        return unless @imap

        @imap&.logout rescue nil
        @imap&.disconnect rescue nil
      rescue StandardError
        nil
      ensure
        @imap = nil
      end

      def imap
        @imap ||= begin
          conn = Net::IMAP.new(
            @imap_config[:host], port: @imap_config[:port],
            ssl: { verify_mode: OpenSSL::SSL::VERIFY_PEER }, open_timeout: OPEN_TIMEOUT
          )
          conn.login(@imap_config[:username], @imap_config[:password])
          @current_mailbox = nil
          conn
        end
      end

      def ensure_mailbox(mailbox)
        return if @current_mailbox == mailbox

        imap.select(mailbox)
        @current_mailbox = mailbox
      end

      def with_lock
        attempts = 0
        @mutex.synchronize do
          yield
        rescue Net::IMAP::ByeResponseError, IOError, Errno::ECONNRESET, Errno::EPIPE => error
          raise if (attempts += 1) > 1

          drop_connection(error)
          retry
        end
      end

      def drop_connection(error)
        $stderr.puts "IMAP connection lost (#{error.class}: #{error.message}), reconnecting..."
        @imap            = nil
        @current_mailbox = nil
      end

      # One UID FETCH answer, or nil when the UID does not exist. Takes no lock: callers hold it (see #with_lock) and
      # have selected the mailbox.
      def fetch(uid, attrs)
        imap.uid_fetch(uid, attrs)&.first
      end

      # UIDVALIDITY of +mailbox+ from STATUS. Takes no lock, like #fetch.
      def uid_validity(mailbox)
        imap.status(mailbox, [ "UIDVALIDITY" ]).fetch("UIDVALIDITY").to_i
      end

      def fetch_raw_mail(uid, fields)
        fetch(uid, fields)&.attr&.[]("RFC822.HEADER")
      end
    end
  end
end
