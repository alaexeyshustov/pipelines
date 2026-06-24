# frozen_string_literal: true

module Evaluation
  class AgentSummaryQuery
    AgentSummary = Data.define(:agent_name, :latest_experiment, :latest_score, :active_prompt_version, :sample_count, :score_history)

    def self.call
      new.call
    end

    def call
      all_experiments = fetch_all_experiments
      return [] if all_experiments.empty?

      prompt_names = extract_prompt_names(all_experiments)
      grouped      = group_by_agent(all_experiments)
      latest       = latest_per_agent(grouped)
      eval_stats   = fetch_stats_data(all_experiments, latest)
      active_vers  = active_versions_for(prompt_names)

      build_agent_summaries(prompt_names, grouped, latest, eval_stats[:latest_stats], eval_stats[:history_avgs], active_vers)
    end

    private

    def extract_prompt_names(experiments)
      experiments.filter_map { |e| e.prompt&.name&.to_s }.uniq
    end

    def fetch_stats_data(all_experiments, latest)
      latest_ids   = latest.values.compact.map(&:id)
      all_stats    = fetch_evaluation_stats(all_experiments.map(&:id))
      {
        history_avgs: build_history_averages(all_stats),
        latest_stats: build_latest_stats(all_stats, latest_ids)
      }
    end

    def fetch_all_experiments
      Evaluation::Experiment
        .joins(:prompt)
        .includes(:prompt)
        .order(:created_at)
        .to_a # : Array[Evaluation::Experiment]
    end

    def fetch_evaluation_stats(experiment_ids)
      Evaluation::EvaluationResult
        .where(experiment_id: experiment_ids)
        .group(:experiment_id)
        .pluck(:experiment_id, Arel.sql("ROUND(COALESCE(AVG(score), NULL), 2)"), Arel.sql("COUNT(*)"))
        .to_a # : Array[[Integer, Float?, Integer]]
    end

    def build_history_averages(stats_rows)
      collector = Hash.new # : Hash[Integer, Float?]
      stats_rows.each_with_object(collector) do |(experiment_id, avg, _), memo|
        memo[experiment_id] = avg&.to_f
      end
    end

    def build_latest_stats(stats_rows, latest_ids)
      collector = Hash.new # : Hash[Integer, { avg: Float?, count: Integer }]
      stats_rows.each_with_object(collector) do |(experiment_id, avg, count), memo|
        memo[experiment_id] = { avg: avg&.to_f, count: count } if latest_ids.include?(experiment_id)
      end
    end

    def build_agent_summaries(prompt_names, grouped, latest, latest_stats, history_avgs, active_vers)
      prompt_names.map do |name|
        exps = grouped[name] || []
        exp = latest[name]
        stats = exp ? latest_stats[exp.id] : nil

        AgentSummary.new(
          agent_name: name,
          latest_experiment: exp,
          latest_score: stats&.dig(:avg),
          active_prompt_version: active_vers[name],
          sample_count: stats&.dig(:count) || 0,
          score_history: build_score_history(exps, history_avgs)
        )
      end
    end

    def group_by_agent(experiments)
      pairs = experiments.filter_map do |experiment|
        prompt = experiment.prompt
        next if prompt.nil?

        [ prompt.name.to_s, experiment ]
      end
      result = pairs.group_by(&:first).transform_values { |p| p.map(&:last) } # : Hash[String, Array[Evaluation::Experiment]]
      result
    end

    def latest_per_agent(grouped)
      grouped.transform_values(&:last)
    end

    def build_score_history(experiments, avgs_by_id)
      experiments.map do |exp|
        avg = avgs_by_id[exp.id]
        { created_at: exp.created_at.strftime("%Y-%m-%d"), avg_score: avg&.to_f&.round(2)&.to_f }
      end
    end

    def active_versions_for(agent_names)
      collector = Hash.new # : Hash[String, Integer?]
      fetch_active_prompts(agent_names).each_with_object(collector) do |prompt, versions|
        key = prompt.name.to_s
        versions[key] = prompt.version unless versions.key?(key)
      end
    end

    def fetch_active_prompts(agent_names)
      Evaluation::Prompt
        .where(name: agent_names)
        .where("json_extract(metadata, '$.active') = ?", true)
        .order(version: :desc)
        .to_a # : Array[Evaluation::Prompt]
    end
  end
end
