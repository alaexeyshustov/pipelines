module Emails
  # Remembers which messages the list and search tools returned in one chat, so
  # the get and add-labels tools can refuse ids the model never listed.
  class MessageScope
    INBOX = "INBOX".freeze

    def self.refusal(message_id)
      { error: "Message #{message_id} was not returned by list_emails or search_emails in this chat. List or search for it first." }
    end

    def initialize
      @keys = Set.new
      @mutex = Mutex.new
    end

    def record(messages)
      return messages unless messages.is_a?(Array)

      keys = messages.filter_map { |message| key_for(message) }
      @mutex.synchronize { @keys.merge(keys) }
      messages
    end

    def allow?(provider:, message_id:, mailbox: nil)
      key = provider == Emails::YAHOO ? [ provider, normalize_mailbox(mailbox), message_id ] : [ provider, message_id ]
      @mutex.synchronize { @keys.include?(key) }
    end

    def bind(tool_classes)
      tool_classes.map do |tool_class|
        next tool_class unless tool_class.respond_to?(:message_scoped?) && tool_class.message_scoped? # steep:ignore

        scoped_class = tool_class #: _ScopedToolClass
        scoped_class.new(message_scope: self)
      end
    end

    private

    def key_for(message)
      return unless message.is_a?(Hash) && !message[:id].nil?

      provider = message[:provider]
      id = message[:id].to_s
      return [ provider, id ] unless provider == Emails::YAHOO

      [ provider, normalize_mailbox(message[:labels]&.first), id ]
    end

    def normalize_mailbox(mailbox)
      (mailbox.presence || INBOX).downcase
    end
  end
end
