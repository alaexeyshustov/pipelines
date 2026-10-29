module Evaluation
  class Grader
    # Persists Grades: one EvaluationResult (+ Justification) per grade, in one transaction via insert_all!.
    class ResultWriter
      EVALUATOR_CLASS = "Evaluation::Grader".freeze

      def self.call(grades:, experiment:, dataset_sample:, sample:)
        new(grades:, experiment:, dataset_sample:, sample:).call
      end

      def initialize(grades:, experiment:, dataset_sample:, sample:)
        @grades = grades
        @experiment = experiment
        @dataset_sample = dataset_sample
        @sample = sample
      end

      def call
        return [] if @grades.empty?

        ids = [] #: Array[Integer]
        ActiveRecord::Base.transaction do
          inserted = EvaluationResult.insert_all!(result_rows) # : ActiveRecord::Result
          ids = inserted.map { |row| Integer(row["id"]) }
          Justification.insert_all!(justification_rows(ids))
        end
        EvaluationResult.where(id: ids).order(:id).to_a
      end

      private

      def result_rows
        @grades.map do |grade|
          {
            experiment_id: @experiment.id, dataset_sample_id: @dataset_sample.id, sample_id: @sample.id,
            evaluator_class: EVALUATOR_CLASS, score: grade.score, raw: grade.raw,
            confidence: grade.confidence, passed: grade.passed
          }
        end
      end

      def justification_rows(ids)
        ids.zip(@grades).map do |id, grade|
          { evaluation_result_id: id, metric_name: grade&.metric_name, justification: grade&.justification }
        end
      end
    end
  end
end
