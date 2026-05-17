module Evaluation
  class EvaluationResult < ApplicationRecord
    self.table_name = "evaluation_evaluation_results"
    belongs_to :experiment, class_name: "Evaluation::Experiment", optional: true
    belongs_to :dataset_record, class_name: "Evaluation::DatasetRecord"
    belongs_to :runner_result, class_name: "Evaluation::RunnerResult"
    has_many :justifications, class_name: "Evaluation::Justification", dependent: :destroy, foreign_key: :evaluation_result_id
    validates :evaluator_class, presence: true
  end
end
