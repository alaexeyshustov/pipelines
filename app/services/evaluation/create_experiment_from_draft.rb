# frozen_string_literal: true

module Evaluation
  class CreateExperimentFromDraft
    def self.call(draft:)
      new(draft: draft).call
    end

    def initialize(draft:)
      @draft = draft
    end

    def call
      # TODO: add transaction
      resolve_prompt
      raise NoMetricsError, "No active metrics for #{@agent_name}" if no_active_metrics?
      experiment = create_experiment!
      ExperimentJob.perform_later(experiment)
      draft.destroy
      experiment
    end

    private

    attr_reader :draft

    def payload
      @payload ||= draft.payload || {}
    end

    def resolve_prompt
      @prompt_id = payload["prompt_id"].presence ||
                   Prompt
                     .where(name: payload["agent_name"])
                     .order(version: :desc, id: :desc)
                     .pick(:id)
                     &.to_s
      @agent_name = Prompt.find_by(id: @prompt_id)&.name
    end

    def no_active_metrics?
      @agent_name.present? && Metric.for_agent(@agent_name).active.none?
    end

    def create_experiment!
      Experiment.create!(
        name:              payload["experiment_name"].presence || "Manual eval",
        dataset_id:        payload["dataset_id"],
        prompt_id:         @prompt_id,
        evaluator_classes: [ "Evaluation::Evaluators::LLMJudgeEval" ],
        metadata:          { "triggered_by" => "manual" },
        sample_model:      payload["sample_model"].presence,
        evaluation_model:  payload["evaluation_model"].presence
      )
    end
  end
end
