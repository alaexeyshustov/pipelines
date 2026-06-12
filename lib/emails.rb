module Emails
  PROVIDERS = {
    "gmail" => Emails::Adapters::GmailAdapter,
    "yahoo" => Emails::Adapters::YahooAdapter
  }.freeze

  def self.configure(**providers_config)
    registry = @provider_registry = ProviderRegistry.new(PROVIDERS)

    providers_config.each do |provider_name, config|
      name          = provider_name.to_s
      adapter_class = PROVIDERS.fetch(name) do
        raise ArgumentError, "Unknown provider '#{name}'. Available: #{PROVIDERS.keys.join(', ')}"
      end
      registry.register(name, adapter_class.from_env(config))
    end
  end

  def self.search_messages(provider_name, query, max_results: 10, offset: 0, label: nil)
    fetch(provider_name).search_messages(query, max_results:, offset:, label:)
  end

  def self.list_messages(provider_name, max_results: 10, after_date: nil, before_date: nil, offset: 0, label: nil)
    fetch(provider_name).list_messages(max_results:, after_date:, before_date:, offset:, label:)
  end

  def self.get_message(provider_name, message_id, label: nil)
    fetch(provider_name).get_message(message_id, label:)
  end

  def self.get_labels(provider_name)
    fetch(provider_name).get_labels
  end

  def self.get_unread_count(provider_name)
    fetch(provider_name).get_unread_count
  end

  def self.modify_labels(provider_name, message_id, add: [], remove: [], source_mailbox: nil)
    fetch(provider_name).modify_labels(message_id, add: add, remove: remove, source_mailbox: source_mailbox)
  end

  def self.create_label(provider_name, name:)
    fetch(provider_name).create_label(name:)
  end

  def self.registry
    @provider_registry ||= ProviderRegistry.new(PROVIDERS)
  end
  private_class_method :registry

  def self.fetch(provider_name)
    registry.fetch(provider_name)
  end
  private_class_method :fetch
end
