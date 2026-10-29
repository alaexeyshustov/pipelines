module Evaluation
  class DashboardController < ApplicationController
    def show
      @agent_summaries = AgentSummaryQuery.call
      @experiments = Evaluation::Experiment.includes(:prompt).order(created_at: :desc)
      @usage_by_experiment = ExperimentUsageQuery.call(experiment_ids: @experiments.map(&:id))
      @pass_rates = PassRateQuery.call(experiment_ids: @experiments.map(&:id))
    end
  end
end
