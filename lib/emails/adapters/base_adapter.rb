module Emails
  module Adapters
    class BaseAdapter
      def self.from_env(**_opts)
        raise NotImplementedError, "#{self}.from_env is not implemented. Subclasses must implement this method to initialize from environment variables."
      end

      def self.setup(**_opts); end
      def self.test_connection(**_opts); end
      def self.reset(**_opts); end

      def on_init; end
      def on_exit; end

      def list_messages(**opts)
        raise NotImplementedError, "#{self.class}#list_messages is not implemented"
      end

      def get_message(message_id, **opts)
        raise NotImplementedError, "#{self.class}#get_message is not implemented"
      end

      def search_messages(query, **opts)
        raise NotImplementedError, "#{self.class}#search_messages is not implemented"
      end

      def get_labels(**opts)
        raise NotImplementedError, "#{self.class}#get_labels is not implemented"
      end

      def get_unread_count(**opts)
        raise NotImplementedError, "#{self.class}#get_unread_count is not implemented"
      end

      def modify_labels(message_id, add: [], remove: [], **opts)
        raise NotImplementedError, "#{self.class}#modify_labels is not implemented"
      end

      def create_label(name:, **opts)
        raise NotImplementedError, "#{self.class}#create_label is not implemented"
      end
    end
  end
end
