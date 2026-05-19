# frozen_string_literal: true

module Evaluation
  module Wizard
    class Step4Form
      def initialize(draft_payload:)
        @payload = draft_payload
      end

      def agent_name      = @payload["agent_name"]
      def experiment_name = @payload["experiment_name"]
      def prompt          = Evaluation::Prompt.find_by(id: @payload["prompt_id"])
      def dataset         = Evaluation::Dataset.find_by(id: @payload["dataset_id"])
      def metrics_count   = Evaluation::Metric.for_agent(agent_name).active.count
    end
  end
end
