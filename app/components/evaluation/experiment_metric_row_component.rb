module Evaluation
  class ExperimentMetricRowComponent < ViewComponent::Base
    def initialize(metric:, avg:, experiment:, pass_rate: nil)
      @metric     = metric
      @avg        = avg
      @experiment = experiment
      @pass_rate  = pass_rate
    end

    def avg_label
      ScoreFormatter.percent(@avg) if @avg
    end

    def pass_rate_label
      "#{ScoreFormatter.percent(@pass_rate)} pass" if @pass_rate
    end

    def metric_results_path
      helpers.metric_results_evaluation_experiment_path(@experiment, metric_name: @metric.name)
    end
  end
end
