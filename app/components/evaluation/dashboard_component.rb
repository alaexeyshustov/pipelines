module Evaluation
  class DashboardComponent < ViewComponent::Base
    def initialize(summary:)
      @summary = summary
    end

    def agent_name = @summary.agent_name
    def latest_experiment = @summary.latest_experiment
    def latest_score = @summary.latest_score
    def active_prompt_version = @summary.active_prompt_version
    def sample_count = @summary.sample_count
    def score_over_time_data = @summary.score_history

    def format_score(score)
      score.nil? ? "—" : score.to_s
    end
  end
end
