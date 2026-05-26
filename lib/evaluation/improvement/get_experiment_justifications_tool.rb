# frozen_string_literal: true

module Evaluation
  module Improvement
    class GetExperimentJustificationsTool < ::RubyLLM::Tool
      description "Fetch all justifications for a specific experiment. Returns the judge's reasoning for every metric on every sample — use this to understand why an experiment scored the way it did."

      param :experiment_id, type: :integer, desc: "ID of the experiment to fetch justifications from.", required: true

      def name = "get_experiment_justifications"

      def execute(experiment_id:)
        Justification
          .eager_load(:evaluation_result)
          .where(evaluation_evaluation_results: { experiment_id: experiment_id })
          .map do |j|
            {
              metric_name: j.metric_name,
              score: j.evaluation_result.score,
              justification: j.justification
            }
          end
      end
    end
  end
end
