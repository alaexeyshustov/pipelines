module Emails
  class RetrievalService
    PAGE_SIZE = 100

    def self.call(provider:, after_date:, before_date: nil) = new(provider:, after_date:, before_date:).call

    def initialize(provider:, after_date:, before_date: nil)
      @provider    = provider
      @after_date  = to_date(after_date)
      @before_date = before_date.nil? ? nil : to_date(before_date)
    end

    def call
      emails = [] #: Array[email_hash]
      offset = 0
      loop do
        page = fetch_page(offset)
        emails.concat(page.map { |email| normalize(email) })
        offset += PAGE_SIZE
        break if page.size < PAGE_SIZE
      end
      emails
    end

    private

    def fetch_page(offset)
      Emails.list_messages(@provider, max_results: PAGE_SIZE, after_date: @after_date, before_date: @before_date, offset: offset)
    end

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
