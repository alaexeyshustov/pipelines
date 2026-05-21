# frozen_string_literal: true

module Evaluation
  class RunEvalJob < ApplicationJob
    queue_as :default

    # TODO: move to s state machine: init -> samples -> evals -> done
    # TODO: rename runner results into samples

    def perform(experiment_id, dataset_record_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      dataset_record = Evaluation::DatasetRecord.find(dataset_record_id)
      run = experiment.runner_class.constantize.new
      evals = experiment.evaluator_classes.compact.reject(&:empty?).map(&:constantize).map(&:new)
      runner_result = run.execute_and_store(experiment, dataset_record, experiment.prompt)
      evals.each { |e| e.evaluate_and_store(experiment, runner_result) }
      experiment.update!(status: :completed) if last?(experiment)
    end

    private

    def last?(experiment)
      experiment.dataset.dataset_records.count == experiment.runner_results.count
    end
  end
end
