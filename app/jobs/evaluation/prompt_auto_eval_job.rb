module Evaluation
  class PromptAutoEvalJob < ApplicationJob
    queue_as :default

    def perform(prompt_id:)
      prompt = Orchestration::Prompt.find(prompt_id)

      previous_experiment = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: prompt.name })
        .where(status: :completed)
        .order(id: :desc)
        .first

      unless previous_experiment
        logger.info("[PromptAutoEvalJob] No completed experiment for '#{prompt.name}', skipping.")
        return
      end

      experiment = Leva::Experiment.create!(
        name: "Auto-eval for #{prompt.name} v#{prompt.version}",
        dataset: previous_experiment.dataset,
        prompt: prompt,
        runner_class: "StubbedAgentRun",
        evaluator_classes: [ "LLMJudgeEval" ],
        metadata: { triggered_by: "prompt_change" }
      )

      Leva::ExperimentJob.perform_later(experiment)
    rescue ActiveRecord::RecordInvalid => e
      logger.error("[PromptAutoEvalJob] Experiment creation failed: #{e.message}")
    end
  end
end
