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
      metric_deltas     = compute_metric_deltas(baseline_metrics, candidate_metrics)

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

    def compute_metric_deltas(baseline_metrics, candidate_metrics)
      all_metric_names = (baseline_metrics.keys | candidate_metrics.keys)
      all_metric_names.index_with do |name|
        b = baseline_metrics[name]
        c = candidate_metrics[name]
        (b && c) ? c - b : nil
      end
    end

    def per_metric_averages(experiment)
      EvaluationResult.per_metric_averages(experiment)
    end

    def overall_average(experiment)
      EvaluationResult.where(experiment: experiment).average(:score) # : Float?
    end
  end
end
