module Emails
  class FetchExecutor
    include Orchestration::Executable

    DEFAULT_DATE = Date.today.to_s
    DEFAULT_PROVIDERS = %w[gmail yahoo].freeze

    def self.call(input, _params = {})
      # TODO: add date ranges
      date  = Date.parse(input.fetch("date", DEFAULT_DATE))
      after = date - 1
      providers = input.fetch("providers", DEFAULT_PROVIDERS)

      emails = Sync do
        semaphore = Async::Semaphore.new(5)
        providers.map do |provider|
          semaphore.async do
            Emails.list_messages(provider, after_date: after, before_date: date)
          end
        end.flat_map(&:wait)
      end

      { "emails" => emails }
    end
  end
end
