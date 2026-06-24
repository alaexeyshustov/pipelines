# frozen_string_literal: true

module Evaluation
  class ExperimentMetricRowComponentPreview < ViewComponent::Preview
    def default
      experiment = Evaluation::Experiment.new(id: 1, name: "Experiment #1",
                                              dataset: Evaluation::Dataset.new(id: 1, name: "Demo"))
      metric     = Evaluation::Metric.new(id: 1, name: "accuracy", agent_name: "ClassifyAgent")
      render(Evaluation::ExperimentMetricRowComponent.new(metric: metric, avg: 85.42, experiment: experiment))
    end

    def no_avg
      experiment = Evaluation::Experiment.new(id: 1, name: "Experiment #1",
                                              dataset: Evaluation::Dataset.new(id: 1, name: "Demo"))
      metric     = Evaluation::Metric.new(id: 1, name: "coherence", agent_name: "ClassifyAgent")
      render(Evaluation::ExperimentMetricRowComponent.new(metric: metric, avg: nil, experiment: experiment))
    end
  end
end
