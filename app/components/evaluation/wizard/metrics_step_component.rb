# frozen_string_literal: true

module Evaluation
  module Wizard
    class MetricsStepComponent < ViewComponent::Base
      def initialize(agent_name:, metrics:)
        @agent_name = agent_name
        @metrics    = metrics
      end

      def metrics_list_id
        "metrics-list-#{@agent_name}"
      end

      def empty?
        @metrics.empty?
      end
    end
  end
end
