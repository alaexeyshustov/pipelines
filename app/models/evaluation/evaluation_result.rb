module Evaluation
  class EvaluationResult < ApplicationRecord
    self.table_name = "evaluation_evaluation_results"
    belongs_to :experiment, class_name: "Evaluation::Experiment", optional: true
    belongs_to :dataset_record, class_name: "Evaluation::DatasetRecord"
    belongs_to :runner_result, class_name: "Evaluation::RunnerResult"
    has_many :justifications, class_name: "Evaluation::Justification", dependent: :destroy, foreign_key: :evaluation_result_id
    validates :evaluator_class, presence: true

    def self.per_metric_averages(experiment)
      results_table        = arel_table
      justifications_table = Justification.arel_table

      joins(
        results_table.join(justifications_table)
          .on(justifications_table[:evaluation_result_id].eq(results_table[:id]))
          .join_sources
      )
        .where(experiment: experiment)
        .group(justifications_table[:metric_name])
        .average(results_table[:score])
        .transform_keys(&:to_s)
    end
  end
end
