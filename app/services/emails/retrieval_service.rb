module Emails
  class RetrievalService
    PAGE_SIZE = 100

    def initialize(provider:, after_date:, before_date: nil)
      @provider    = provider
      @after_date  = to_date(after_date)
      @before_date = before_date.nil? ? nil : to_date(before_date)
    end

    def call
      page = Emails.list_messages(
        @provider,
        max_results: PAGE_SIZE,
        after_date: @after_date,
        before_date: @before_date,
        offset: 0
      )
      emails = page.map { |email| normalize(email) }
      offset = PAGE_SIZE

      while page.size == PAGE_SIZE
        page = Emails.list_messages(
          @provider,
          max_results: PAGE_SIZE,
          after_date: @after_date,
          before_date: @before_date,
          offset: offset
        )
        emails.concat(page.map { |email| normalize(email) })
        offset += PAGE_SIZE
      end

      emails
    end

    private

    def to_date(date)
      Date.parse(date.to_s)
    end

    def normalize(email)
      {
        "id"       => email[:id].to_s,
        "subject"  => email[:subject].to_s,
        "provider" => @provider,
        "date"     => email[:date].to_s,
        "from"     => email[:from].to_s
      }
    end
  end
end
