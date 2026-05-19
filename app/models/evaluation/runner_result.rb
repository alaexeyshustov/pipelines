module Evaluation
  class RunnerResult < ApplicationRecord
    self.table_name = "evaluation_runner_results"
    belongs_to :experiment, class_name: "Evaluation::Experiment", optional: true
    belongs_to :dataset_record, class_name: "Evaluation::DatasetRecord"
    belongs_to :prompt, class_name: "Evaluation::Prompt"
    has_many :evaluation_results, dependent: :destroy, class_name: "Evaluation::EvaluationResult"
    validates :prediction, :prompt, :runner_class, presence: true
    delegate :ground_truth, to: :dataset_record
  end
end
