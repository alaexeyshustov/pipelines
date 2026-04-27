module Emails
  module Adapters
    class BaseAdapter
      def self.from_env(**_opts)
        raise NotImplementedError, "#{self}.from_env is not implemented. Subclasses must implement this method to initialize from environment variables."
      end

      def self.setup(**_kwargs); end
      def self.test_connection(**_kwargs); end
      def self.reset; end

      def on_init; end
      def on_exit; end

      def search_messages(query, max_results: 1, offset: 0, label: nil)
        raise NotImplementedError, "#{self.class}#search_messages is not implemented"
      end

      def list_messages(max_results: 1, after_date: nil, before_date: nil, offset: 0, label: nil)
        raise NotImplementedError, "#{self.class}#list_messages is not implemented"
      end

      def get_message(message_id, label: nil)
        raise NotImplementedError, "#{self.class}#get_message is not implemented"
      end

      def get_labels
        raise NotImplementedError, "#{self.class}#get_labels is not implemented"
      end

      def get_unread_count
        raise NotImplementedError, "#{self.class}#get_unread_count is not implemented"
      end

      def modify_labels(message_id, add: [], remove: [], source_mailbox: nil)
        raise NotImplementedError, "#{self.class}#modify_labels is not implemented"
      end

      def create_label(name:)
        raise NotImplementedError, "#{self.class}#create_label is not implemented"
      end
    end
  end
end
