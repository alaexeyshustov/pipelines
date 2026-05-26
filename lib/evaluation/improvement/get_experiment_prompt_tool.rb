# frozen_string_literal: true

module Evaluation
  module Improvement
    class GetExperimentPromptTool < ::RubyLLM::Tool
      description "Fetch the prompt text used in a specific experiment. Use this to understand what instructions produced a given set of scores."

      param :experiment_id, type: :integer, desc: "ID of the experiment to fetch the prompt from.", required: true

      def name = "get_experiment_prompt"

      def execute(experiment_id:)
        experiment = Experiment.includes(:prompt).find_by(id: experiment_id)
        return nil unless experiment&.prompt

        {
          system_prompt: experiment.prompt.system_prompt.to_s,
          user_prompt: experiment.prompt.user_prompt,
          output_schema: experiment.prompt.output_schema
        }
      end
    end
  end
end
