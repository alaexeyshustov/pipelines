module Evaluation
  class PromptAutoEvalJob < ApplicationJob
    queue_as :default

    def perform(prompt_id:)
      prompt              = Evaluation::Prompt.find(prompt_id)
      previous_experiment = find_previous_experiment(prompt)

      unless previous_experiment
        logger.info("[PromptAutoEvalJob] No completed experiment for '#{prompt.name}', skipping.")
        return
      end

      experiment = create_auto_eval_experiment(prompt, previous_experiment)
      Evaluation::ExperimentJob.perform_later(experiment)
    rescue ActiveRecord::RecordInvalid => e
      logger.error("[PromptAutoEvalJob] Experiment creation failed: #{e.message}")
    end

    private

    def find_previous_experiment(prompt)
      Evaluation::Experiment
        .completed_for_prompt_name(prompt.name)
        .order(id: :desc)
        .first
    end

    def create_auto_eval_experiment(prompt, previous_experiment)
      Evaluation::Experiment.create!(
        name: "Auto-eval for #{prompt.name} v#{prompt.version}",
        dataset: previous_experiment.dataset,
        prompt: prompt,
        metadata: { triggered_by: "prompt_change" }
      )
    end
  end
end
