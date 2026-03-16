module Adapters
  class YahooAdapter < BaseAdapter
    def initialize(yahoo_mail_service)
      @service = yahoo_mail_service
    end

    def list_messages(max_results: 10, query: nil, after_date: nil, before_date: nil,
                      offset: 0, mailbox: "INBOX", flagged: nil, **_ignored)
      @service.list_messages(
        mailbox:      mailbox,
        max_results:  max_results,
        query:        query,
        flagged:      flagged,
        after_date:   after_date,
        before_date:  before_date,
        offset:       offset
      )
    end

    def get_message(message_uid, mailbox: "INBOX", **_ignored)
      @service.get_message(message_uid.to_i, mailbox: mailbox)
    end

    def search_messages(query, max_results: 10, mailbox: "INBOX", **_ignored)
      @service.search_messages(query, max_results: max_results, mailbox: mailbox)
    end

    def get_labels(**_ignored)
      @service.get_folders.map do |folder|
        { id: folder[:name], name: folder[:name], type: (folder[:attributes]&.first || "user").to_s }
      end
    end

    def get_unread_count(mailbox: "INBOX", **_ignored)
      @service.get_unread_count(mailbox: mailbox)
    end

    def modify_labels(message_uid, add: [], remove: [], mailbox: "INBOX", **_ignored)
      result = {}
      result = @service.tag_email(message_uid.to_i, tags: add,    mailbox: mailbox, action: "add")    unless add.empty?
      result = @service.tag_email(message_uid.to_i, tags: remove, mailbox: mailbox, action: "remove") unless remove.empty?
      result
    end
  end
end
