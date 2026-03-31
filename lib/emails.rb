module Emails
  PROVIDERS = {
    "gmail" => Emails::Adapters::GmailAdapter,
    "yahoo" => Emails::Adapters::YahooAdapter
  }.freeze

  class << self
    def configure(**providers_config)
      @provider_registry = ProviderRegistry.new(PROVIDERS)

      providers_config.each do |provider_name, config|
        name          = provider_name.to_s
        adapter_class = PROVIDERS.fetch(name) do
          raise ArgumentError, "Unknown provider '#{name}'. Available: #{PROVIDERS.keys.join(', ')}"
        end
        @provider_registry.register(name, adapter_class.from_env(**(config || {})))
      end
    end

    def search_messages(provider_name, query, max_results: 10, offset: 0, label: nil)
      fetch(provider_name).search_messages(query, max_results:, offset:, label:)
    end

    def list_messages(provider_name, max_results: 10, after_date: nil, before_date: nil, offset: 0, label: nil)
      fetch(provider_name).list_messages(max_results:, after_date:, before_date:, offset:, label:)
    end

    def get_message(provider_name, message_id, label: nil)
      fetch(provider_name).get_message(message_id, label:)
    end

    def get_labels(provider_name)
      fetch(provider_name).get_labels
    end

    def get_unread_count(provider_name)
      fetch(provider_name).get_unread_count
    end

    def modify_labels(provider_name, message_id, add: [], remove: [])
      fetch(provider_name).modify_labels(message_id, add: add, remove: remove)
    end

    def create_label(provider_name, name:)
      fetch(provider_name).create_label(name:)
    end

    private

    def registry
      @provider_registry ||= ProviderRegistry.new(PROVIDERS)
    end

    def fetch(provider_name)
      registry.fetch(provider_name)
    end
  end
end
