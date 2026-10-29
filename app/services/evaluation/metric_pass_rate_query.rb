module Evaluation
  # Pass rate (0.0..1.0) per metric name within one experiment; see PassRateQuery.
  class MetricPassRateQuery
    def self.call(experiment:)
      new(experiment:).call
    end

    def initialize(experiment:)
      @experiment = experiment
    end

    def call
      name = Justification.arel_table[:metric_name]
      rows = EvaluationResult.joins(EvaluationResult.justification_join_source)
                             .where(experiment: @experiment).where.not(passed: nil)
                             .group(name).pluck(name, PassRateQuery::PASS_RATE)
      rows.to_h { |metric_name, rate| [ metric_name.to_s, Float(rate) ] }
    end
  end
end
