module Evaluation
  class Dataset < ApplicationRecord
    self.table_name = "evaluation_datasets"
    has_many :dataset_records, class_name: "Evaluation::DatasetRecord", dependent: :destroy
    has_many :experiments, class_name: "Evaluation::Experiment", dependent: :destroy
    validates :name, presence: true
  end
end
