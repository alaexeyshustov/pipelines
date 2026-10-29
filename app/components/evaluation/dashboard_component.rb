module Evaluation
  class DashboardComponent < ViewComponent::Base
    # pass_rate / usage describe the latest experiment (Evaluation::PassRateQuery, Evaluation::ExperimentUsageQuery).
    def initialize(summary:, pass_rate: nil, usage: nil)
      @summary = summary
      @pass_rate = pass_rate
      @usage = usage
    end

    def agent_name = @summary.agent_name
    def latest_experiment = @summary.latest_experiment
    def latest_score = @summary.latest_score
    def active_prompt_version = @summary.active_prompt_version
    def sample_count = @summary.sample_count
    def score_over_time_data = @summary.score_history

    def latest_pass_rate = @pass_rate
    def latest_usage = @usage

    def format_score(score) = ScoreFormatter.percent(score)
    def format_pass_rate(rate) = ScoreFormatter.percent(rate)

    def usage_label
      usage = latest_usage
      return "—" if usage.nil? || usage.calls.zero?

      "#{ScoreFormatter.cost(usage.cost)} · #{ScoreFormatter.tokens(usage.total_tokens)} tokens"
    end
  end
end
