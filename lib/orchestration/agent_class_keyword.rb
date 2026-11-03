module Orchestration
  module AgentClassKeyword
    class UnknownKeyword < StandardError; end

    PREFIX = "agent_".freeze

    def self.encode(klass_or_name)
      name = klass_or_name.to_s
      raise UnknownKeyword, "Unknown agent class: #{name}" unless ServiceRegistry::REGISTRY.key?(name)

      "#{PREFIX}#{name.demodulize.underscore}"
    end

    def self.decode(keyword)
      ServiceRegistry::REGISTRY.each_key.find { |name| encode(name) == keyword } ||
        raise(UnknownKeyword, "Unknown agent keyword: #{keyword}")
    end
  end
end
