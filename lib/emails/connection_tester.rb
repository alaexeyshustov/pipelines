module Emails
  # Probes a provider connection using a connector's configuration.
  # Pure collaborator: performs no persistence; callers own status updates.
  class ConnectionTester
    UNKNOWN_PROVIDER = "Unknown provider".freeze
    GENERIC_ERROR    = "Could not connect with the saved settings".freeze

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
      { success: false, error: GENERIC_ERROR, exception: e }
    end

    private

    def run_provider_check(adapter_class)
      case @provider
      when Emails::GMAIL then connect_gmail_adapter(adapter_class)
      when Emails::YAHOO then connect_yahoo_adapter(adapter_class)
      end
    end

    # from_env returns an authorized adapter; fetching the profile proves the token works.
    def connect_gmail_adapter(adapter_class)
      adapter_class.from_env.profile
    end

    # Only the connector's own credentials: a blank one must not fall back to the server's YAHOO_* account.
    def connect_yahoo_adapter(adapter_class)
      username = config_value(:username)
      password = config_value(:password)
      raise Emails::NotConfigured, "Yahoo connector has no stored username or password" if username.blank? || password.blank?

      adapter_class.from_env(username:, password:).list_messages(max_results: 1)
    end

    def config_value(key)
      @configuration[key]&.to_s
    end
  end
end
