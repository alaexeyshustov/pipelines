require "date"
require "json"
require "async"
require "async/semaphore"

module Pipeline
  class EmailProviderFetcher
    def initialize(date:)
      @date = date
    end

    def call
      tmp_file = Rails.root.join("tmp", "emails_#{@date - 1}_#{@date}.json")
      if File.exist?(tmp_file)
        cached = JSON.parse(tmp_file.read)
        return cached.filter_map { |email| email if email.is_a?(Hash) } if cached.is_a?(Array)
      end

      emails = fetch_from_providers
      tmp_file.write(emails.to_json)
      emails
    end

    private

    def fetch_from_providers
      Sync { run_provider_tasks }
    end

    def run_provider_tasks
      Async::Helpers.with_semaphore(5) do |semaphore|
        [ "gmail", "yahoo" ].map do |provider|
          semaphore.async do
            result = Emails::RetrievalService.call(provider: provider, after_date: @date - 1, before_date: @date)
            normalize_provider_result(result)
          end
        end
      end
    end

    def normalize_provider_result(result)
      if result.is_a?(Array)
        filter_hash_emails(result)
      elsif result.is_a?(Hash)
        normalize_hash_result(result)
      else
        []
      end
    end

    def filter_hash_emails(emails)
      emails.filter_map { |email| email if email.is_a?(Hash) }
    end

    def normalize_hash_result(result)
      results = result["results"]
      results.is_a?(Array) ? filter_hash_emails(results) : []
    end
  end
end
