# frozen_string_literal: true

module Evaluation
  module Wizard
    class Step2Form
      def initialize(draft_payload:)
        @payload = draft_payload
      end

      def agent_name = @payload["agent_name"]
      def metrics    = Evaluation::Metric.for_agent(agent_name).order(:name)
    end
  end
end
