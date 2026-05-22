module Evaluation
  class Sample < ApplicationRecord
    self.table_name = "evaluation_samples"

    belongs_to :experiment, class_name: "Evaluation::Experiment", optional: true
    belongs_to :dataset_sample, class_name: "Evaluation::DatasetSample"
    belongs_to :prompt, class_name: "Evaluation::Prompt"

    validates :dataset_sample, :prompt, presence: true
  end
end
