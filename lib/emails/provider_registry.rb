module Emails
  class ProviderRegistry
    class UnknownProviderError < StandardError; end

    def initialize(known_adapters = {})
      @adapters       = {}
      @known_adapters = known_adapters
    end

    def register(name, adapter)
      @adapters[name.to_s] = adapter
    end

    def fetch(name)
      @adapters[name.to_s] || auto_load(name.to_s)
    end

    def providers
      @adapters.keys
    end

    def on_init
      @adapters.each_value(&:on_init)
    end

    def on_exit
      @adapters.each_value(&:on_exit)
    end

    private

    def auto_load(name)
      adapter_class = @known_adapters[name] || raise(
        UnknownProviderError,
        "Unknown provider '#{name}'. Available: #{@known_adapters.keys.join(', ')}"
      )
      adapter = adapter_class.from_env
      register(name, adapter)
      adapter
    end
  end
end
