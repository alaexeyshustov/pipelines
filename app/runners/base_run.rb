# frozen_string_literal: true

class BaseRun
  def execute(record)
    raise NotImplementedError, "#{self.class}#execute must be implemented"
  end

  def execute_and_store(experiment, dataset_record, prompt)
    @experiment = experiment
    @prompt = prompt
    @dataset_record = dataset_record
    result = execute(dataset_record.recordable)
    Evaluation::RunnerResult.create!(
      experiment: experiment,
      dataset_record: dataset_record,
      prompt: prompt,
      prediction: result,
      runner_class: self.class.name
    )
  end
end
