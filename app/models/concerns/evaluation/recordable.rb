module Evaluation
  module Recordable
    extend ActiveSupport::Concern
    included do
      has_many :dataset_records, as: :recordable, class_name: "Evaluation::DatasetRecord", dependent: :destroy
      has_many :datasets, through: :dataset_records, class_name: "Evaluation::Dataset"
      has_many :runner_results, through: :dataset_records, class_name: "Evaluation::RunnerResult"
      has_many :evaluation_results, through: :runner_results, class_name: "Evaluation::EvaluationResult"
    end
    def ground_truth = raise NotImplementedError
    def index_attributes = raise NotImplementedError
    def show_attributes = raise NotImplementedError
    def to_llm_context = raise NotImplementedError
    def extract_regex_pattern = false
  end
end
