module Adapters
  class BaseAdapter
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
  end
end
