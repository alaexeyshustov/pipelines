module Evaluation
  # Cost / token usage and pass rates shown next to the scores of an experiment (see ExperimentUsageQuery,
  # PassRateQuery, MetricPassRateQuery).
  module ExperimentStats
    extend ActiveSupport::Concern

    private

    def load_experiment_stats(experiment)
      @usage = ExperimentUsageQuery.call(experiment_ids: [ experiment.id ])[experiment.id]
      @pass_rate = PassRateQuery.call(experiment_ids: [ experiment.id ])[experiment.id]
      @metric_pass_rates = MetricPassRateQuery.call(experiment: experiment)
    end
  end
end
