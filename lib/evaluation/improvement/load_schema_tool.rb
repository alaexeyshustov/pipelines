module Evaluation
  module Improvement
    class LoadSchemaTool < ::RubyLLM::Tool
      description "Fetch output schema for the experiment"

      param :prompt_name, type: :string, desc: "Name of the prompt being to load schmea from.", required: true

      def name = "load_schema"

      def execute(prompt_name)
        schema = schema_for(prompt_name)
        return unless schema

        schema.output_schema
      end

      private

      def schema_for(prompt_name)
        ::Orchestration::Agent.find_by(name: prompt_name)
      end
    end
  end
end
