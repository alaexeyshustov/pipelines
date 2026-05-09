# frozen_string_literal: true

module Evaluation
  class DashboardController < ApplicationController
    def show
      @agent_summaries = agent_summaries
    end

    private

    AgentSummary = Data.define(:agent_name, :latest_experiment, :latest_score, :active_prompt_version, :sample_count)

    def agent_summaries
      prompt_names = Leva::Experiment.joins(:prompt).distinct.pluck("leva_prompts.name")
      prompt_names.map { |name| build_summary(name) }
    end

    def build_summary(agent_name)
      experiments = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: agent_name })
        .order(created_at: :desc)

      latest = experiments.first
      score = latest ? average_score(latest) : nil
      count = latest ? Leva::EvaluationResult.where(experiment_id: latest.id).count : 0
      version = active_version(agent_name)

      AgentSummary.new(
        agent_name: agent_name,
        latest_experiment: latest,
        latest_score: score,
        active_prompt_version: version,
        sample_count: count
      )
    end

    def average_score(experiment)
      avg = Leva::EvaluationResult.where(experiment_id: experiment.id).average(:score)
      avg&.to_f&.round(2)
    end

    def active_version(agent_name)
      Orchestration::Prompt.where(name: agent_name).find_each do |p|
        meta = JSON.parse(p.metadata || "{}")
        return p.version if meta["active"]
      rescue JSON::ParserError
        next
      end
      nil
    end
  end
end
