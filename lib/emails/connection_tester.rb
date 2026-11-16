module Emails
  # Probes a provider connection using a connector's configuration.
  # Pure collaborator: performs no persistence; callers own status updates.
  class ConnectionTester
    UNKNOWN_PROVIDER = "Unknown provider".freeze

    def initialize(provider:, configuration:, providers: Emails::PROVIDERS)
      @provider      = provider.to_s
      @configuration = configuration.to_h.with_indifferent_access
      @providers     = providers
    end

    def call
      adapter_class = @providers[@provider]
      return { success: false, error: UNKNOWN_PROVIDER } unless adapter_class

      run_provider_check(adapter_class)
      { success: true }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    private

    def run_provider_check(adapter_class)
      case @provider
      when Emails::GMAIL then connect_gmail_adapter(adapter_class)
      when Emails::YAHOO then connect_yahoo_adapter(adapter_class)
      end
    end

    def connect_gmail_adapter(adapter_class)
      adapter = adapter_class.from_env(
        credentials_path: config_value(:credentials_path),
        token_path: config_value(:token_path)
      )
      adapter.on_init
      adapter.instance_variable_get(:@service).get_user_profile("me")
    end

    def connect_yahoo_adapter(adapter_class)
      adapter = adapter_class.from_env(
        host: config_value(:host),
        port: config_value(:port).presence&.to_i,
        username: config_value(:username),
        password: config_value(:password)
      )
      adapter.list_messages(max_results: 1)
    end

    def config_value(key)
      @configuration[key]&.to_s
    end
  end
end
