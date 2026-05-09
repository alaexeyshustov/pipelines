# frozen_string_literal: true

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

    def score_over_time_data
      experiments = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: agent_name })
        .order(:created_at)

      experiments.map do |exp|
        avg = Leva::EvaluationResult.where(experiment_id: exp.id).average(:score)
        {
          id: exp.id,
          name: exp.name,
          created_at: exp.created_at.strftime("%Y-%m-%d"),
          avg_score: avg&.to_f&.round(2)
        }
      end
    end

    def format_score(score)
      score.nil? ? "—" : score.to_s
    end
  end
end
