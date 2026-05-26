# frozen_string_literal: true

module Evaluation
  class EvaluationJob < ApplicationJob
    queue_as :default

    retry_on RubyLLM::Error, attempts: 3 do |job, _error|
      experiment = Evaluation::Experiment.find_by(id: job.arguments[0])
      next unless experiment

      job.decrement_and_maybe_complete(experiment)
    end

    def perform(experiment_id, sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      sample = Evaluation::Sample.find(sample_id)

      transition_to_evaluating(experiment)
      Evaluation::Evaluators::LLMJudgeEval.new.evaluate_and_store(experiment, sample)

      decrement_and_maybe_complete(experiment)
    end

    def decrement_and_maybe_complete(experiment)
      experiment.with_lock do
        experiment.decrement!(:pending_evaluations_count)
        experiment.complete! if experiment.pending_evaluations_count.zero? && experiment.may_complete?
      end
    end

    private

    def transition_to_evaluating(experiment)
      experiment.with_lock do
        experiment.start_evaluating! if experiment.may_start_evaluating?
      end
    end
  end
end
