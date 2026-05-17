# frozen_string_literal: true

module Evaluation
  class DashboardController < ApplicationController
    AgentSummary = Data.define(:agent_name, :latest_experiment, :latest_score, :active_prompt_version, :sample_count, :score_history)

    def show
      @agent_summaries = agent_summaries
      @experiments = Evaluation::Experiment.includes(:prompt).order(created_at: :desc)
    end

    private

    # TODO: move this logic out of controller
    def agent_summaries
      prompt_names = Evaluation::Experiment.joins(:prompt).distinct.pluck("evaluation_prompts.name")
      return [] if prompt_names.empty?

      all_experiments = Evaluation::Experiment
        .joins(:prompt)
        .where(evaluation_prompts: { name: prompt_names })
        .includes(:prompt)
        .order(:created_at)
        .to_a

      experiments_by_agent = all_experiments.group_by { |e| e.prompt.name }
      latest_by_agent = experiments_by_agent.transform_values(&:last)

      latest_ids = latest_by_agent.values.compact.map(&:id)
      latest_stats = batch_stats(latest_ids)

      history_avgs = Evaluation::EvaluationResult
        .where(experiment_id: all_experiments.map(&:id))
        .group(:experiment_id)
        .average(:score)

      active_vers = active_versions_for(prompt_names)

      prompt_names.map do |name|
        exps = experiments_by_agent[name] || []
        latest = latest_by_agent[name]
        stats = latest ? latest_stats[latest.id] : nil

        AgentSummary.new(
          agent_name: name,
          latest_experiment: latest,
          latest_score: stats&.dig(:avg),
          active_prompt_version: active_vers[name],
          sample_count: stats&.dig(:count) || 0,
          score_history: build_score_history(exps, history_avgs)
        )
      end
    end

    def batch_stats(experiment_ids)
      return {} if experiment_ids.empty?

      Evaluation::EvaluationResult
        .where(experiment_id: experiment_ids)
        .group(:experiment_id)
        .pluck(:experiment_id, Arel.sql("AVG(score)"), Arel.sql("COUNT(*)"))
        .each_with_object({}) do |(exp_id, avg, count), h|
          h[exp_id] = { avg: avg&.to_f&.round(2), count: count }
        end
    end

    def build_score_history(experiments, avgs_by_id)
      experiments.map do |exp|
        avg = avgs_by_id[exp.id]
        { created_at: exp.created_at.strftime("%Y-%m-%d"), avg_score: avg&.to_f&.round(2) }
      end
    end

    def active_versions_for(agent_names)
      Evaluation::Prompt
        .where(name: agent_names)
        .where("metadata LIKE ?", '%"active":true%')
        .each_with_object({}) do |p, h|
          next if h.key?(p.name)

          meta = JSON.parse(p.metadata || "{}")
          h[p.name] = p.version if meta["active"]
        rescue JSON::ParserError
          Rails.logger.warn("Prompt #{p.id} has invalid JSON metadata")
        end
    end
  end
end
