module Evaluation
  class PromptAutoEvalJob < ApplicationJob
    queue_as :default

    def perform(prompt_id)
      prompt = Orchestration::Prompt.find(prompt_id)

      previous_experiment = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: prompt.name })
        .where(status: :completed)
        .order(id: :desc)
        .first

      unless previous_experiment
        Rails.logger.info("[PromptAutoEvalJob] No completed experiment for '#{prompt.name}', skipping.")
        return
      end

      experiment = Leva::Experiment.create!(
        name: "Auto-eval for #{prompt.name} v#{prompt.version}",
        dataset: previous_experiment.dataset,
        prompt: prompt,
        runner_class: "Evaluation::StubbedAgentRun",
        evaluator_classes: [ "LLMJudgeEval" ]
      )

      Leva::ExperimentJob.perform_later(experiment)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[PromptAutoEvalJob] Experiment creation failed: #{e.message}")
    end
  end
end
