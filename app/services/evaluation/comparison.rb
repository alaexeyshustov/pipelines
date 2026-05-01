module Evaluation
  class Comparison
    ComparisonResult = Data.define(:baseline_score, :candidate_score, :baseline_metrics, :candidate_metrics, :metric_deltas, :overall_delta)

    def self.call(baseline_experiment:, candidate_experiment:)
      new(baseline_experiment: baseline_experiment, candidate_experiment: candidate_experiment).call
    end

    def initialize(baseline_experiment:, candidate_experiment:)
      @baseline_experiment  = baseline_experiment
      @candidate_experiment = candidate_experiment
    end

    def call
      baseline_metrics  = per_metric_averages(@baseline_experiment)
      candidate_metrics = per_metric_averages(@candidate_experiment)
      all_metric_names  = (baseline_metrics.keys | candidate_metrics.keys)

      metric_deltas = all_metric_names.index_with do |name|
        b = baseline_metrics[name]
        c = candidate_metrics[name]
        (b && c) ? c - b : nil
      end

      baseline_score  = overall_average(@baseline_experiment)
      candidate_score = overall_average(@candidate_experiment)
      overall_delta   = (baseline_score && candidate_score) ? candidate_score - baseline_score : nil

      ComparisonResult.new(
        baseline_score: baseline_score,
        candidate_score: candidate_score,
        baseline_metrics: baseline_metrics,
        candidate_metrics: candidate_metrics,
        metric_deltas: metric_deltas,
        overall_delta: overall_delta
      )
    end

    private

    def per_metric_averages(experiment)
      conn = Leva::EvaluationResult.connection
      results_table       = conn.quote_table_name(Leva::EvaluationResult.table_name)
      justifications_table = conn.quote_table_name(Evaluation::Justification.table_name)

      Leva::EvaluationResult
        .joins(
          "INNER JOIN #{justifications_table} " \
          "ON #{justifications_table}.evaluation_result_id = #{results_table}.id"
        )
        .where(experiment: experiment)
        .group("#{justifications_table}.metric_name")
        .average("#{results_table}.score")
        .transform_keys(&:to_s)
    end

    def overall_average(experiment)
      Leva::EvaluationResult.where(experiment: experiment).average(:score)
    end
  end
end
