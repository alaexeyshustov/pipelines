module Emails
  module Adapters
    # Lists the ids of INBOX messages for incremental sync: added since a +historyId+, or received since a date.
    class GmailInboxLister
      PAGE_SIZE = 500

      def initialize(service)
        @service = service
      end

      # Ids added to INBOX after +history_id+, without repeats.
      # Raises Emails::HistoryExpiredError when Gmail has dropped that history (404).
      def since(history_id)
        paged_ids { |page_token| added_message_ids(list_history(history_id, page_token)) }
      end

      # Ids of INBOX messages received on or after +date+.
      def after(date)
        paged_ids do |page_token|
          response = @service.list_user_messages("me", max_results: PAGE_SIZE, q: "after:#{date.strftime('%Y/%m/%d')}",
                                                       label_ids: [ "INBOX" ], page_token: page_token)
          [ Array(response&.messages).filter_map(&:id), response&.next_page_token ]
        end
      end

      private

      def paged_ids
        ids = Array.new
        page_token = nil
        loop do
          page_ids, page_token = yield(page_token)
          ids.concat(page_ids)
          break unless page_token
        end
        ids.uniq
      end

      def list_history(history_id, page_token)
        @service.list_user_histories("me", start_history_id: history_id, history_types: [ "messageAdded" ],
                                           label_id: "INBOX", page_token: page_token)
      rescue Google::Apis::ClientError => error
        raise Emails::HistoryExpiredError, "Gmail history #{history_id} is gone" if error.status_code == 404

        raise
      end

      def added_message_ids(response)
        ids = Array(response&.history).flat_map do |history|
          Array(history.messages_added).filter_map { |added| added.message&.id }
        end
        [ ids, response&.next_page_token ]
      end
    end
  end
end
