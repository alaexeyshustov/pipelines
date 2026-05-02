module Evaluation
  class PromptAutoEvalJob < ApplicationJob
    queue_as :default

    def perform(prompt)
      previous_experiment = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: prompt.name })
        .where(status: :completed)
        .order(id: :desc)
        .first

      return unless previous_experiment

      experiment = Leva::Experiment.create!(
        name: "Auto-eval for #{prompt.name} v#{prompt.version}",
        dataset: previous_experiment.dataset,
        prompt: prompt,
        runner_class: "Evaluation::StubbedAgentRun",
        evaluator_classes: [ "LLMJudgeEval" ]
      )

      Leva::ExperimentJob.perform_later(experiment)
    end
  end
end
