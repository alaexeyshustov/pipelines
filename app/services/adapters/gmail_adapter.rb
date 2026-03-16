module Adapters
  class GmailAdapter < BaseAdapter
    def initialize(gmail_service)
      @service = gmail_service
    end

    def list_messages(max_results: 10, query: nil, after_date: nil, before_date: nil,
                      offset: 0, label: nil, **_ignored)
      @service.list_messages(
        max_results:  max_results,
        query:        query,
        after_date:   after_date,
        before_date:  before_date,
        offset:       offset,
        label_ids:    label ? [ label ] : nil
      )
    end

    def get_message(message_id, **_ignored)
      @service.get_message(message_id.to_s)
    end

    def search_messages(query, max_results: 10, **_ignored)
      @service.search_messages(query, max_results: max_results)
    end

    def get_labels(**_ignored)
      @service.get_labels
    end

    def get_unread_count(**_ignored)
      @service.get_unread_count
    end

    def modify_labels(message_id, add: [], remove: [], **_ignored)
      @service.modify_labels(message_id.to_s, add_label_ids: add, remove_label_ids: remove)
    end
  end
end
