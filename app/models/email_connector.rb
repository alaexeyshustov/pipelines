class EmailConnector < ApplicationRecord
  serialize :configuration, type: Hash, coder: JSON

  before_save :convert_configuration_to_hash

  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: %w[gmail yahoo] }

  def test_connection
    adapter_class = resolve_adapter_class
    return { success: false, error: "Unknown provider" } unless adapter_class

    probe_connection(adapter_class)
  end

  private

  def resolve_adapter_class
    case provider
    when "gmail"  then Emails::Adapters::GmailAdapter
    when "yahoo"  then Emails::Adapters::YahooAdapter
    end
  end

  def probe_connection(adapter_class)
    run_provider_check(adapter_class)
    update(status: "connected", last_connected_at: Time.current)
    { success: true }
  rescue StandardError => e
    update(status: "failed")
    { success: false, error: e.message }
  end

  def run_provider_check(adapter_class)
    case provider
    when "gmail" then connect_gmail_adapter(adapter_class)
    when "yahoo" then connect_yahoo_adapter(adapter_class)
    end
  end

  def connect_gmail_adapter(adapter_class)
    adapter = adapter_class.from_env(
      credentials_path: configuration[:credentials_path],
      token_path: configuration[:token_path]
    )
    adapter.on_init
    adapter.instance_variable_get(:@service).get_user_profile("me")
  end

  def connect_yahoo_adapter(adapter_class)
    adapter = adapter_class.new(
      host: configuration[:host],
      port: configuration[:port].to_i,
      username: configuration[:username],
      password: configuration[:password]
    )
    adapter.list_messages(max_results: 1)
  end

  def convert_configuration_to_hash
    self.configuration = configuration.to_h.deep_transform_keys(&:to_s).to_h if configuration.respond_to?(:to_h)
  end
end
