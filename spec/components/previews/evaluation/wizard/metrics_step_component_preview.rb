# frozen_string_literal: true

module Evaluation
  module Wizard
    class MetricsStepComponentPreview < ViewComponent::Preview
      def default
        metrics = [
          Evaluation::Metric.new(id: 1, name: "accuracy", agent_name: "ClassifyAgent"),
          Evaluation::Metric.new(id: 2, name: "relevance", agent_name: "ClassifyAgent")
        ]
        form = OpenStruct.new(agent_name: "ClassifyAgent", metrics: metrics)
        render(Evaluation::Wizard::MetricsStepComponent.new(form: form))
      end

      def empty
        form = OpenStruct.new(agent_name: "NewAgent", metrics: [])
        render(Evaluation::Wizard::MetricsStepComponent.new(form: form))
      end
    end
  end
end
