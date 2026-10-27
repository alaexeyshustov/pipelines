# frozen_string_literal: true

module Evaluation
  module Improvement
    class GetExperimentPromptTool < ::RubyLLM::Tool
      description "Fetch the prompt text used in a specific experiment. Use this to understand what instructions produced a given set of scores."

      parameter :experiment_id, type: :integer, description: "ID of the experiment to fetch the prompt from.", required: true

      def name = "get_experiment_prompt"

      def execute(experiment_id:)
        experiment = Experiment.find_by(id: experiment_id)
        return nil unless experiment

        prompt = experiment.prompt
        return nil unless prompt

        {
          system_prompt: prompt.system_prompt.to_s,
          user_prompt: prompt.user_prompt.to_s,
          output_schema: prompt.output_schema
        }
      end
    end
  end
end
