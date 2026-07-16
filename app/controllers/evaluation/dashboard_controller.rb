
module Evaluation
  class DashboardController < ApplicationController
    def show
      @agent_summaries = AgentSummaryQuery.call
      @experiments = Evaluation::Experiment.includes(:prompt).order(created_at: :desc)
    end
  end
end
