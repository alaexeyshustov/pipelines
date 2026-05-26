module Emails
  class FetchExecutor
    include Orchestration::Executable

    DEFAULT_DATE        = Date.today.to_s
    DEFAULT_PROVIDERS   = %w[gmail yahoo].freeze
    DEFAULT_MAX_RESULTS = 10

    input_schema(
      date:        { "type" => "string" },
      providers:   { "type" => "array", "items" => { "type" => "string" } },
      max_results: { "type" => "integer" }
    )

    def self.call(date: nil, providers: DEFAULT_PROVIDERS, max_results: DEFAULT_MAX_RESULTS, **)
      parsed_date = Date.parse(date || DEFAULT_DATE)
      after       = parsed_date - 1
      providers   = DEFAULT_PROVIDERS if providers.nil?
      max_results = (max_results || DEFAULT_MAX_RESULTS).to_i

      emails = Sync do
        semaphore = Async::Semaphore.new(5)
        providers.map do |provider|
          semaphore.async do
            Emails.list_messages(provider, max_results:, after_date: after, before_date: parsed_date)
          end
        end.flat_map(&:wait)
      end

      { "emails" => emails }
    end
  end
end
