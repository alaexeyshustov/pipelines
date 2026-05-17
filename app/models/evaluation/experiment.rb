module Evaluation
  class Experiment < ApplicationRecord
    self.table_name = "evaluation_experiments"
    belongs_to :dataset, class_name: "Evaluation::Dataset"
    belongs_to :prompt, class_name: "Evaluation::Prompt", optional: true
    has_many :runner_results, class_name: "Evaluation::RunnerResult", dependent: :destroy
    has_many :evaluation_results, through: :runner_results, class_name: "Evaluation::EvaluationResult"
    validates :name, :dataset, :runner_class, :evaluator_classes, presence: true
    enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }, default: :pending
    serialize :evaluator_classes, coder: JSON, type: Array
    serialize :metadata, coder: JSON
  end
end
