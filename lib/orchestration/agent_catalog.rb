module Orchestration
  module AgentCatalog
    Metadata = Data.define(:name, :model, :prompt, :output_schema) do
      def self.from(agent) = new(name: agent.name, model: agent.model,
                                  prompt: agent.prompt, output_schema: agent.output_schema)
    end

    def self.find(name)
      agent = Orchestration::Agent.named(name)
      agent && Metadata.from(agent)
    end
  end
end
