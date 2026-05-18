module Evaluation
  class EvaluationResult < ApplicationRecord
    self.table_name = "evaluation_evaluation_results"
    belongs_to :experiment, class_name: "Evaluation::Experiment", optional: true
    belongs_to :dataset_record, class_name: "Evaluation::DatasetRecord"
    belongs_to :runner_result, class_name: "Evaluation::RunnerResult"
    has_many :justifications, class_name: "Evaluation::Justification", dependent: :destroy, foreign_key: :evaluation_result_id
    validates :evaluator_class, presence: true

    def self.per_metric_averages(experiment)
      conn = connection
      results_table        = conn.quote_table_name(table_name)
      justifications_table = conn.quote_table_name(Justification.table_name)

      joins(
        "INNER JOIN #{justifications_table} " \
        "ON #{justifications_table}.evaluation_result_id = #{results_table}.id"
      )
        .where(experiment: experiment)
        .group("#{justifications_table}.metric_name")
        .average("#{results_table}.score")
        .transform_keys(&:to_s)
    end
  end
end
