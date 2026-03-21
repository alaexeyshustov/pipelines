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

    def list_messages(provider_name, **opts)
      fetch(provider_name).list_messages(**opts)
    end

    def get_message(provider_name, message_id, **opts)
      fetch(provider_name).get_message(message_id, **opts)
    end

    def search_messages(provider_name, query, **opts)
      fetch(provider_name).search_messages(query, **opts)
    end

    def get_labels(provider_name, **opts)
      fetch(provider_name).get_labels(**opts)
    end

    def get_unread_count(provider_name, **opts)
      fetch(provider_name).get_unread_count(**opts)
    end

    def modify_labels(provider_name, message_id, add: [], remove: [], **opts)
      fetch(provider_name).modify_labels(message_id, add: add, remove: remove, **opts)
    end

    def create_label(provider_name, name:, **opts)
      fetch(provider_name).create_label(name: name, **opts)
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
