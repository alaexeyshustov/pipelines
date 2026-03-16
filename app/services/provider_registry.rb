class ProviderRegistry
  class UnknownProviderError < StandardError; end

  def initialize
    @adapters = {}
  end

  def register(name, adapter)
    @adapters[name.to_s] = adapter
  end

  def fetch(name)
    @adapters.fetch(name.to_s) do
      raise UnknownProviderError,
            "Unknown provider '#{name}'. Available: #{@adapters.keys.join(', ')}"
    end
  end

  def providers
    @adapters.keys
  end
end
