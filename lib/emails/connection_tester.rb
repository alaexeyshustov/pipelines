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
      when "gmail" then connect_gmail_adapter(adapter_class)
      when "yahoo" then connect_yahoo_adapter(adapter_class)
      end
    end

    def connect_gmail_adapter(adapter_class)
      adapter = adapter_class.from_env(
        credentials_path: @configuration[:credentials_path],
        token_path: @configuration[:token_path]
      )
      adapter.on_init
      adapter.instance_variable_get(:@service).get_user_profile("me")
    end

    def connect_yahoo_adapter(adapter_class)
      adapter = adapter_class.from_env(
        host: @configuration[:host],
        port: @configuration[:port].presence&.to_i,
        username: @configuration[:username],
        password: @configuration[:password]
      )
      adapter.list_messages(max_results: 1)
    end
  end
end
