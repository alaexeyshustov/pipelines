module Evaluation
  module Improvement
    class LoadSchemaTool < ::RubyLLM::Tool
      description "Fetch output schema for the experiment"

      parameter :prompt_name, type: :string, description: "Name of the prompt being to load schmea from.", required: true

      def name = "load_schema"

      def execute(prompt_name)
        ::Orchestration::AgentCatalog.find(prompt_name)&.output_schema
      end
    end
  end
end
