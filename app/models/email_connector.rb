class EmailConnector < ApplicationRecord
  serialize :configuration, type: Hash, coder: JSON

  before_save :convert_configuration_to_hash

  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: %w[gmail yahoo] }

  def test_connection
    adapter_class = case provider
    when "gmail"
                      Emails::Adapters::GmailAdapter
    when "yahoo"
                      Emails::Adapters::YahooAdapter
    else
                      return { success: false, error: "Unknown provider" }
    end

    # For Gmail, it currently expects credentials.json and token.yaml on disk.
    # We might want to extend it to take configuration from the DB.
    # For now, let's try to use the existing `test_connection` class method.

    begin
      case provider
      when "gmail"
        # GmailAdapter.test_connection currently prints to stdout and doesn't return value
        # We might need to refactor it or capture output
        adapter = adapter_class.from_env(
          credentials_path: configuration[:credentials_path],
          token_path: configuration[:token_path]
        )
        adapter.on_init
        adapter.instance_variable_get(:@service).get_user_profile("me")
      when "yahoo"
        adapter = adapter_class.new(
          host: configuration[:host],
          port: configuration[:port].to_i,
          username: configuration[:username],
          password: configuration[:password]
        )
        adapter.list_messages(max_results: 1)
      end

      update(status: "connected", last_connected_at: Time.current)
      { success: true }
    rescue StandardError => e
      update(status: "failed")
      { success: false, error: e.message }
    end
  end

  private

  def convert_configuration_to_hash
    self.configuration = configuration.to_h.deep_transform_keys(&:to_s).to_h if configuration.respond_to?(:to_h)
  end
end
