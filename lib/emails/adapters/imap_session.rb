module Emails
  module Adapters
    class ImapSession
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
          conn = Net::IMAP.new(@imap_config[:host], port: @imap_config[:port], ssl: true)
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

      # rubocop:disable Metrics/BlockLength
      def with_lock
        attempts = 0
        @mutex.synchronize do
          yield
        rescue Net::IMAP::ByeResponseError, IOError, Errno::ECONNRESET, Errno::EPIPE => error
          raise if (attempts += 1) > 1
          $stderr.puts "IMAP connection lost (#{error.class}: #{error.message}), reconnecting..."
          @imap            = nil
          @current_mailbox = nil
          retry
        end
      end
      # rubocop:enable Metrics/BlockLength

      def fetch_raw_mail(uid, fields)
        result = imap.uid_fetch(uid, fields)&.first&.attr
        result&.values_at("RFC822", "RFC822.HEADER")&.compact&.first
      end
    end
  end
end
