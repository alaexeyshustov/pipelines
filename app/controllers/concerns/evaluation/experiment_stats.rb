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
      @metrics = experiment.agent_name ? Metric.for_agent(experiment.agent_name).order(:name).to_a : []
      @sample_count = experiment.samples.count
    end
  end
end
