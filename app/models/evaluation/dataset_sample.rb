module Evaluation
  class DatasetSample < ApplicationRecord
    self.table_name = "evaluation_dataset_samples"

    belongs_to :dataset, class_name: "Evaluation::Dataset"
    has_many :samples, class_name: "Evaluation::Sample", dependent: :destroy

    validates :input, presence: true
  end
end
