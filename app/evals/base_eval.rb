# frozen_string_literal: true

class BaseEval
  def evaluate(runner_result, recordable)
    raise NotImplementedError, "#{self.class}#evaluate must be implemented"
  end

  def evaluate_and_store(experiment, runner_result)
    @experiment = experiment
    @runner_result = runner_result
    recordable = runner_result.dataset_record.recordable
    result = evaluate(runner_result, recordable)
    Evaluation::EvaluationResult.create!(
      experiment: experiment,
      dataset_record: runner_result.dataset_record,
      runner_result: runner_result,
      score: result,
      evaluator_class: self.class.name
    )
  end
end
