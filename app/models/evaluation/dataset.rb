module Evaluation
  class Dataset < ApplicationRecord
    self.table_name = "evaluation_datasets"
    has_many :dataset_samples, class_name: "Evaluation::DatasetSample", dependent: :destroy
    has_many :experiments, class_name: "Evaluation::Experiment", dependent: :destroy
    SAMPLE_COUNT = 1..50
    DEFAULT_SAMPLE_COUNT = 20

    validates :name, presence: true, length: { maximum: 255 }

    scope :for_agent, ->(name) { where(agent_name: name) }
    scope :with_record_counts, -> {
      left_joins(:dataset_samples)
        .group("evaluation_datasets.id")
        .select("evaluation_datasets.*, COUNT(evaluation_dataset_samples.id) AS record_count")
        .order(:name)
    }
  end
end
