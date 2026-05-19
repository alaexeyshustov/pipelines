module Evaluation
  class Justification < ApplicationRecord
    self.table_name = "evaluation_justifications"

    belongs_to :evaluation_result, class_name: "Evaluation::EvaluationResult"

    validates :metric_name, presence: true
    validates :justification, presence: true
  end
end
