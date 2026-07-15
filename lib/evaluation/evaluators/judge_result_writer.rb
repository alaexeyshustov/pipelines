module Evaluation
  module Evaluators
    class JudgeResultWriter
      def self.call(metric_results:, experiment:, dataset_sample:, sample:, evaluator_class:)
        new(metric_results: metric_results, experiment: experiment, dataset_sample: dataset_sample,
            sample: sample, evaluator_class: evaluator_class).call
      end

      def initialize(metric_results:, experiment:, dataset_sample:, sample:, evaluator_class:)
        @metric_results = metric_results
        @experiment = experiment
        @dataset_sample = dataset_sample
        @sample = sample
        @evaluator_class = evaluator_class
      end

      def call
        inserted_ids = insert_results_transactionally
        load_stored_results(inserted_ids)
      end

      private

      def insert_results_transactionally
        eval_results = build_eval_results
        inserted_ids = [] #: Array[Integer]
        ActiveRecord::Base.transaction do
          inserted = EvaluationResult.insert_all!(eval_results) # : ActiveRecord::Result
          inserted_ids = inserted.map { |row| Integer(row["id"]) } # : Array[Integer]
          Justification.insert_all!(build_justifications(inserted_ids))
        end
        inserted_ids
      end

      def build_eval_results
        @metric_results.map do |result|
          {
            experiment_id: @experiment.id,
            dataset_sample_id: @dataset_sample.id,
            sample_id: @sample.id,
            score: Float(result[:score]),
            evaluator_class: @evaluator_class
          }
        end
      end

      def build_justifications(inserted_ids)
        inserted_ids.zip(@metric_results).filter_map do |id, result|
          next unless result

          {
            evaluation_result_id: id,
            metric_name: result[:metric_name],
            justification: result[:justification]
          }
        end
      end

      def load_stored_results(inserted_ids)
        results       = EvaluationResult.where(id: inserted_ids).to_a # : Array[EvaluationResult]
        results_by_id = results.index_by(&:id) # : Hash[Integer, EvaluationResult]
        inserted_ids.filter_map { |id| results_by_id[id] }
      end
    end
  end
end
