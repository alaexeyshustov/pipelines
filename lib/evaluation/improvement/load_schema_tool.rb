module Evaluation
  module Improvement
    class LoadSchemaTool < ::RubyLLM::Tool
      description "Fetch output schema for the experiment"

      param :prompt_name, type: :string, desc: "Name of the prompt being to load schmea from.", required: true

      def name = "load_schema"

      def execute(prompt_name)
        ::Orchestration::AgentCatalog.find(prompt_name)&.output_schema
      end
    end
  end
end
