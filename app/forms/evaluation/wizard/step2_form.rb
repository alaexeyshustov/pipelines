# frozen_string_literal: true

module Evaluation
  module Wizard
    class Step2Form < ::BaseForm
      validate :active_metrics_present

      def initialize(draft_payload:)
        @payload = draft_payload
      end

      def advance!(_payload)
        return true if agent_name.blank?
        return true if Evaluation::Metric.for_agent(agent_name).active.any?
        errors.add(:base, "Please generate or add at least one active metric before continuing.")
        false
      end

      def agent_name = @payload["agent_name"]
      def metrics    = Evaluation::Metric.for_agent(agent_name).order(:name)

      private

      def active_metrics_present
        return if agent_name.blank?
        return if Evaluation::Metric.for_agent(agent_name).active.any?
        errors.add(:base, "No active metrics exist for this agent. Please go back to the Metrics step and generate or add metrics.")
      end
    end
  end
end
