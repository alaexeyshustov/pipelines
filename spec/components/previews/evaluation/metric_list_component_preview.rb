
module Evaluation
  class MetricListComponentPreview < ViewComponent::Preview
    def default
      metrics = [
        Evaluation::Metric.new(id: 1, name: "accuracy", agent_name: "ClassifyAgent"),
        Evaluation::Metric.new(id: 2, name: "relevance", agent_name: "ClassifyAgent"),
        Evaluation::Metric.new(id: 3, name: "coherence", agent_name: "ClassifyAgent")
      ]
      render(Evaluation::MetricListComponent.new(metrics: metrics))
    end

    def empty
      render(Evaluation::MetricListComponent.new(metrics: []))
    end
  end
end
