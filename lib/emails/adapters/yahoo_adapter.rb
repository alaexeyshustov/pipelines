module Emails
  module Adapters
    class YahooAdapter < BaseAdapter
      def self.setup(**_kwargs)
        puts "Yahoo setup:"
        puts "1. Sign in to your Yahoo account and go to Account Security settings."
        puts "2. Generate an app password for 'Mail' and 'Other device'."
        puts "3. Set YAHOO_USERNAME to your Yahoo email and YAHOO_APP_PASSWORD to the generated password in your environment variables."
        puts "4. Run `bin/cli test` to test the connection."
      end

      def self.test_connection(**kwargs)
        connection = from_env(**kwargs)
        connection.list_messages(max_results: 1)
        puts "✓ Yahoo Mail connection successful"
      rescue StandardError => error
        puts "ERROR: Yahoo Mail connection failed - #{error.message}"
      end

      def self.from_env(
        username: ENV["YAHOO_USERNAME"],
        password: ENV["YAHOO_APP_PASSWORD"],
        host:     ENV.fetch("YAHOO_IMAP_HOST", "imap.mail.yahoo.com"),
        port:     ENV.fetch("YAHOO_IMAP_PORT", "993").to_i
      )
        raise "Missing Yahoo credentials. Please set YAHOO_USERNAME and YAHOO_APP_PASSWORD environment variables." unless username && password

        new(host:, port:, username:, password:)
      end

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

      def search_messages(query, max_results: 100, offset: 0, label: nil)
        mailbox = build_mailbox(label)

        with_lock do
          ensure_mailbox(mailbox)
          criteria = ImapSearchCriteria.new(query: query).build
          uids = imap.uid_search(criteria).sort.reverse
          uids = uids[offset, max_results] || []
          uids.map { |uid| list_message(uid, mailbox) }.compact
        end
      end

      def list_messages(max_results: 100, after_date: nil, before_date: nil, offset: 0, label: nil)
        mailbox = build_mailbox(label)

        with_lock do
          ensure_mailbox(mailbox)
          criteria = ImapSearchCriteria.new(after_date: after_date, before_date: before_date).build
          uids = imap.uid_search(criteria).sort.reverse
          uids = uids[offset, max_results] || []
          uids.map { |uid| list_message(uid, mailbox) }.compact
        end
      end

      def get_message(message_id, label: nil)
        uid     = message_id.to_i
        mailbox = build_mailbox(label)

        with_lock do
          ensure_mailbox(mailbox)
          mail = parse_mail(uid, FULL_FIELDS)
          raise "Message not found: #{message_id}" unless mail

          YahooMessageParser.new(uid, mail, mailbox).to_h.merge(body: ImapBodyParser.new(mail).body)
        end
      end

      def get_labels
        @labels ||= with_lock do
          (imap.list("", "*") || []).map do |mb|
            fname = mb.name
            { id: fname, name: fname, type: (Array(mb.attr).map(&:to_s).first || "user") }
          end
        end
      end

      def get_unread_count
        with_lock { imap.status("INBOX", [ "UNSEEN" ])["UNSEEN"] || 0 }
      end

      def create_label(name:)
        with_lock { imap.create(name) }
        { id: name, name: name, type: "user" }
      rescue Net::IMAP::NoResponseError => error
        raise error unless error.message.include?("CREATE failed - Mailbox exists")

        { id: name, name: name, type: "user" }
      end

      def modify_labels(message_uid, add: [], remove: [], source_mailbox: "INBOX")
        uid = message_uid.to_i

        unless add.empty?
          with_lock do
            ensure_mailbox(source_mailbox)
            add.each do |label|
              if imap_flag?(label)
                imap.uid_store(uid, "+FLAGS", [ label ])
              else
                imap.uid_copy(uid, label)
              end
            end
          end
        end

        remove.each do |label|
          with_lock do
            if imap_flag?(label)
              ensure_mailbox(source_mailbox)
              imap.uid_store(uid, "-FLAGS", [ label ])
            else
              ensure_mailbox(label)
              imap.uid_store(uid, "+FLAGS", [ :Deleted ])
              imap.expunge
            end
          end
        end

        { message_id: uid, added: add, removed: remove }
      end

      HEADER_FIELDS = %w[RFC822.HEADER FLAGS UID].freeze
      FULL_FIELDS   = %w[RFC822 FLAGS UID].freeze

      private

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

      def parse_mail(uid, fields)
        result = imap.uid_fetch(uid, fields)&.first&.attr
        raw    = result&.values_at("RFC822", "RFC822.HEADER")&.compact&.first
        return nil if raw.blank?

        Mail.new(raw)
      rescue StandardError => error
        $stderr.puts "Warning: failed to parse message UID #{uid}: #{error.message}"
        nil
      end

      def list_message(uid, mailbox)
        mail = parse_mail(uid, HEADER_FIELDS)
        return nil unless mail

        YahooMessageParser.new(uid, mail, mailbox).to_h
      end

      def build_mailbox(label)
        return "INBOX" if label.blank?

        match = get_labels.find do |lbl|
          [ lbl[:id], lbl[:name] ].compact.any? { |value| value.casecmp?(label) }
        end

        match&.dig(:name) || label
      end

      def imap_flag?(label)
        label.start_with?("\\")
      end
    end
  end
end
