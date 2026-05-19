# frozen_string_literal: true

module Evaluation
  module Wizard
    class MetricsStepComponent < ViewComponent::Base
      def initialize(form:)
        @form = form
      end

      def agent_name = @form.agent_name
      def metrics    = @form.metrics

      def metrics_list_id
        "metrics-list-#{agent_name}"
      end

      def empty?
        metrics.empty?
      end
    end
  end
end
