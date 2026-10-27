module Evaluation
  class ExperimentMetricRowComponent < ViewComponent::Base
    def initialize(metric:, avg:, experiment:)
      @metric     = metric
      @avg        = avg
      @experiment = experiment
    end

    def avg_label
      format("%.2f", @avg) if @avg
    end

    def metric_results_path
      helpers.metric_results_evaluation_experiment_path(@experiment, metric_name: @metric.name)
    end
  end
end
