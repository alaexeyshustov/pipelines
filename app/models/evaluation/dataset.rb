module Evaluation
  class Dataset < ApplicationRecord
    self.table_name = "evaluation_datasets"
    has_many :dataset_samples, class_name: "Evaluation::DatasetSample", dependent: :destroy
    has_many :experiments, class_name: "Evaluation::Experiment", dependent: :destroy
    validates :name, presence: true
  end
end
