# frozen_string_literal: true

module Evaluation
  class EvaluationJob < ApplicationJob
    queue_as :default

    ALLOWED_EVALUATORS = %w[Evaluation::Evaluators::LLMJudgeEval].freeze

    retry_on StandardError, attempts: 3 do |job, _error|
      experiment = Evaluation::Experiment.find_by(id: job.arguments[0])
      next unless experiment

      job.decrement_and_maybe_complete(experiment)
    end

    def perform(experiment_id, sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      sample = Evaluation::Sample.find(sample_id)

      evaluators_for(experiment).each { |e| e.evaluate_and_store(experiment, sample) }

      decrement_and_maybe_complete(experiment)
    end

    def decrement_and_maybe_complete(experiment)
      experiment.with_lock do
        experiment.decrement!(:pending_evaluations_count)
        experiment.complete! if experiment.pending_evaluations_count.zero? && experiment.may_complete?
      end
    end

    private

    def evaluators_for(experiment)
      experiment.evaluator_classes.compact.reject(&:empty?).map do |klass|
        raise ArgumentError, "Unrecognised evaluator class: #{klass}" unless ALLOWED_EVALUATORS.include?(klass)

        klass.constantize.new
      end
    end
  end
end
