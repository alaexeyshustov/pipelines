module Evaluation
  # Cost / token usage and pass rates shown next to the scores of an experiment (see ExperimentUsageQuery,
  # PassRateQuery, MetricPassRateQuery).
  module ExperimentStats
    extend ActiveSupport::Concern
    include Evaluation::ActivePromptLookup

    private

    def load_experiment_stats(experiment)
      @usage = ExperimentUsageQuery.call(experiment_ids: [ experiment.id ]).by_experiment[experiment.id]
      load_pass_rates(experiment)
      @metrics = experiment.agent_name ? Metric.for_agent(experiment.agent_name).order(:name).to_a : []
      @sample_count = experiment.samples.count
      @active_prompt = active_prompt_for(experiment.prompt)
    end

    def load_pass_rates(experiment)
      @pass_rate = PassRateQuery.call(experiment_ids: [ experiment.id ]).by_experiment[experiment.id]
      @metric_pass_rates = MetricPassRateQuery.call(experiment: experiment).by_metric
    end
  end
end
