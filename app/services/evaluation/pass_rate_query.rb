module Evaluation
  # Share of graded results that passed their metric's minimum (evaluation_evaluation_results.passed), per
  # experiment id (0.0..1.0). Results without a verdict (passed IS NULL: unknown score or no minimum) are ignored;
  # experiments without any verdict are absent from the result.
  class PassRateQuery
    PASS_RATE = Arel.sql("AVG(CASE WHEN evaluation_evaluation_results.passed THEN 1.0 ELSE 0.0 END)")

    def self.call(experiment_ids:)
      new(experiment_ids:).call
    end

    def initialize(experiment_ids:)
      @experiment_ids = experiment_ids
    end

    def call
      rows = EvaluationResult.where(experiment_id: @experiment_ids).where.not(passed: nil)
                             .group(:experiment_id).pluck(:experiment_id, PASS_RATE)
      rows.to_h { |id, rate| [ Integer(id), Float(rate) ] }
    end
  end
end
