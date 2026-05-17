module Evaluation
  class DatasetRecord < ApplicationRecord
    self.table_name = "evaluation_dataset_records"
    belongs_to :dataset, class_name: "Evaluation::Dataset"
    belongs_to :recordable, polymorphic: true
    has_many :runner_results, class_name: "Evaluation::RunnerResult", dependent: :destroy
    has_many :evaluation_results, through: :runner_results, class_name: "Evaluation::EvaluationResult"
    validates :dataset, :recordable, presence: true
    delegate :ground_truth, to: :recordable
  end
end
