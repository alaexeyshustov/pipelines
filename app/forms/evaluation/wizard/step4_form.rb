module Evaluation
  module Wizard
    class Step4Form < ::BaseForm
      def initialize(draft_payload:)
        @payload = draft_payload
      end

      def advance!(_payload) = true

      def agent_name      = @payload["agent_name"]
      def experiment_name = @payload["experiment_name"]
      def metrics_count   = Evaluation::Metric.for_agent(agent_name).active.count

      # Memoized: the review step renders each of these more than once.
      def prompt
        return @prompt if defined?(@prompt)

        @prompt = Evaluation::Prompt.find_by(id: @payload["prompt_id"])
      end

      def dataset
        return @dataset if defined?(@dataset)

        @dataset = Evaluation::Dataset.find_by(id: @payload["dataset_id"])
      end
    end
  end
end
