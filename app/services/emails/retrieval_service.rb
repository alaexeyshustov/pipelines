module Emails
  class RetrievalService
    PAGE_SIZE = 100

    def initialize(provider:, after_date:, before_date: nil)
      @provider    = provider
      @after_date  = after_date.is_a?(String) ? Date.parse(after_date) : after_date
      @before_date = before_date ? (before_date.is_a?(String) ? Date.parse(before_date) : before_date) : nil
    end

    def call
      emails = []
      offset = 0

      loop do
        page = Emails.list_messages(
          @provider,
          max_results:  PAGE_SIZE,
          after_date:   @after_date,
          before_date:  @before_date,
          offset:       offset
        )

        emails.concat(page.map { |e| normalize(e) })
        break if page.size < PAGE_SIZE

        offset += PAGE_SIZE
      end

      emails
    end

    private

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
