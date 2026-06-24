module Evaluation
  class Sample < ApplicationRecord
    self.table_name = "evaluation_samples"

    belongs_to :experiment, class_name: "Evaluation::Experiment"
    belongs_to :dataset_sample, class_name: "Evaluation::DatasetSample"
    belongs_to :prompt, class_name: "Evaluation::Prompt"
    has_many :evaluation_results, class_name: "Evaluation::EvaluationResult", dependent: :destroy
  end
end
