module Emails
  class FetchExecutor
    DEFAULT_DATE = Date.today.to_s
    DEFAULT_PROVIDERS = %w[gmail yahoo].freeze
    DEFAULT_MAX_RESULTS = 10

    def self.call(input, params = {})
      date        = Date.parse(input["date"] || DEFAULT_DATE)
      after       = date - 1
      providers   = input["providers"] || DEFAULT_PROVIDERS
      max_results = params.fetch("max_results", DEFAULT_MAX_RESULTS).to_i

      emails = Sync do
        semaphore = Async::Semaphore.new(5)
        providers.map do |provider|
          semaphore.async do
            Emails.list_messages(provider, max_results:, after_date: after, before_date: date)
          end
        end.flat_map(&:wait)
      end

      { "emails" => emails }
    end
  end
end
