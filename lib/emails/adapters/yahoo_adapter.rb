module Emails
  module Adapters
    class YahooAdapter < BaseAdapter
      def self.setup(_opts = {})
        Rails.logger.debug "Yahoo setup:"
        Rails.logger.debug "1. Sign in to your Yahoo account and go to Account Security settings."
        Rails.logger.debug "2. Generate an app password for 'Mail' and 'Other device'."
        Rails.logger.debug "3. Set YAHOO_USERNAME to your Yahoo email and YAHOO_APP_PASSWORD to the generated password in your environment variables."
        Rails.logger.debug "4. Run `bin/cli test` to test the connection."
      end

      def self.test_connection(opts = {})
        connection = from_env(opts)
        connection.list_messages(max_results: 1)
        # rubocop:disable Rails/Output
        puts "✓ Yahoo Mail connection successful"
        # rubocop:enable Rails/Output
      rescue StandardError => error
        # rubocop:disable Rails/Output
        puts "ERROR: Yahoo Mail connection failed - #{error.message}"
        # rubocop:enable Rails/Output
      end

      def self.from_env(opts = {})
        username = opts[:username] || ENV["YAHOO_USERNAME"]
        password = opts[:password] || ENV["YAHOO_APP_PASSWORD"]
        host     = opts[:host]     || ENV.fetch("YAHOO_IMAP_HOST", "imap.mail.yahoo.com")
        port     = opts[:port]     || ENV.fetch("YAHOO_IMAP_PORT", "993").to_i
        raise "Missing Yahoo credentials. Please set YAHOO_USERNAME and YAHOO_APP_PASSWORD environment variables." unless username && password

        new(host:, port:, username:, password:)
      end

      def initialize(host:, port:, username:, password:)
        @session       = ImapSession.new(host: host, port: port, username: username, password: password)
        @label_manager = ImapLabelManager.new(session: @session)
      end

      def on_exit
        @session.on_exit
      end

      def search_messages(query, max_results: 100, offset: 0, label: nil)
        criteria = ImapSearchCriteria.new(query: query).build
        fetch_uids(build_mailbox(label), criteria, max_results, offset)
      end

      def list_messages(max_results: 100, after_date: nil, before_date: nil, offset: 0, label: nil)
        criteria = ImapSearchCriteria.new(after_date: after_date, before_date: before_date).build
        fetch_uids(build_mailbox(label), criteria, max_results, offset)
      end

      def get_message(message_id, label: nil)
        uid     = message_id.to_i
        mailbox = build_mailbox(label)

        @session.with_lock do
          @session.ensure_mailbox(mailbox)
          mail = parse_mail(uid, FULL_FIELDS)
          raise "Message not found: #{message_id}" unless mail

          parsed = YahooMessageParser.new(uid, mail, mailbox).to_h
          to_message(parsed, mail)
        end
      end

      def get_labels
        @labels ||= @session.with_lock do
          (@session.imap.list("", "*") || []).map do |mb|
            fname = mb.name
            { id: fname, name: fname, type: (Array(mb.attr).map(&:to_s).first || "user") }
          end
        end
      end

      def get_unread_count
        @session.with_lock { @session.imap.status("INBOX", [ "UNSEEN" ])["UNSEEN"] || 0 }
      end

      def create_label(name:)
        @label_manager.create_label(name: name)
      end

      def modify_labels(message_uid, add: [], remove: [], source_mailbox: "INBOX")
        uid = message_uid.to_i
        @label_manager.add_labels(uid, add, source_mailbox) unless add.empty?
        @label_manager.remove_labels(uid, remove, source_mailbox)
        { message_id: uid, added: add, removed: remove }
      end

      HEADER_FIELDS = %w[RFC822.HEADER FLAGS UID].freeze
      FULL_FIELDS   = %w[RFC822 FLAGS UID].freeze

      private

      def fetch_uids(mailbox, criteria, max_results, offset)
        @session.with_lock do
          @session.ensure_mailbox(mailbox)
          uids = @session.imap.uid_search(criteria).sort.reverse
          uids = uids[offset, max_results] || []
          uids.filter_map { |uid| parse_mail(uid, HEADER_FIELDS)&.then { |mail| YahooMessageParser.new(uid, mail, mailbox).to_h } }
        end
      end

      def parse_mail(uid, fields)
        raw = @session.fetch_raw_mail(uid, fields)
        return nil if raw.blank?

        Mail.new(raw)
      rescue StandardError => error
        $stderr.puts "Warning: failed to parse message UID #{uid}: #{error.message}"
        nil
      end

      def to_message(parsed, mail)
        {
          id: parsed[:id],
          provider: parsed[:provider],
          subject: parsed[:subject],
          from: parsed[:from],
          to: parsed[:to],
          date: parsed[:date],
          snippet: parsed[:snippet],
          body: ImapBodyParser.new(mail).body,
          labels: parsed[:labels]
        }
      end

      def build_mailbox(label)
        return "INBOX" if label.blank?

        match = get_labels.find do |lbl|
          [ lbl[:id], lbl[:name] ].compact.any? { |value| value.casecmp?(label) }
        end

        match&.dig(:name) || label
      end
    end
  end
end
