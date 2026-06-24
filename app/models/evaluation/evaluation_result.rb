module Evaluation
  class EvaluationResult < ApplicationRecord
    self.table_name = "evaluation_evaluation_results"
    belongs_to :experiment, class_name: "Evaluation::Experiment", optional: true
    belongs_to :dataset_sample, class_name: "Evaluation::DatasetSample", optional: true
    belongs_to :sample, class_name: "Evaluation::Sample", optional: true
    has_many :justifications, class_name: "Evaluation::Justification", dependent: :destroy
    validates :evaluator_class, presence: true

    accepts_nested_attributes_for :justifications, allow_destroy: true

    def self.per_metric_averages(experiment)
      joins(justification_join_source)
        .where(experiment: experiment)
        .group(Justification.arel_table[:metric_name])
        .average(arel_table[:score])
        .transform_keys(&:to_s)
    end

    def self.justification_join_source
      results_table        = arel_table
      justifications_table = Justification.arel_table
      results_table.join(justifications_table)
                   .on(justifications_table[:evaluation_result_id].eq(results_table[:id]))
                   .join_sources
    end
  end
end
