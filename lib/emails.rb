module Emails
  GMAIL = "gmail".freeze
  YAHOO = "yahoo".freeze
  PROVIDER_NAMES = [ GMAIL, YAHOO ].freeze

  PROVIDERS = {
    GMAIL => Emails::Adapters::GmailAdapter,
    YAHOO => Emails::Adapters::YahooAdapter
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

  def self.message(provider_name, message_id, label: nil)
    fetch(provider_name).message(message_id, label:)
  end

  def self.attachment(provider_name, message_id, attachment_id)
    fetch(provider_name).attachment(message_id, attachment_id)
  end

  def self.attachments(provider_name, message_id)
    fetch(provider_name).attachments(message_id)
  end

  def self.profile(provider_name)
    fetch(provider_name).profile
  end

  def self.inbox_message_ids_since(provider_name, history_id)
    fetch(provider_name).inbox_message_ids_since(history_id)
  end

  def self.inbox_message_ids_after(provider_name, date)
    fetch(provider_name).inbox_message_ids_after(date)
  end

  def self.account(provider_name)
    fetch(provider_name).account
  end

  def self.inbox_status(provider_name)
    fetch(provider_name).inbox_status
  end

  def self.inbox_uids_after(provider_name, last_uid)
    fetch(provider_name).inbox_uids_after(last_uid)
  end

  def self.inbox_uids_since(provider_name, date)
    fetch(provider_name).inbox_uids_since(date)
  end

  def self.fetch_message(provider_name, message_id)
    fetch(provider_name).fetch_message(message_id)
  end

  def self.labels(provider_name)
    fetch(provider_name).labels
  end

  def self.unread_count(provider_name)
    fetch(provider_name).unread_count
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
