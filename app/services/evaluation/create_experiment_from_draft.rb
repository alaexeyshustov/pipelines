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
      resolve_prompt
      maybe_auto_generate_metrics
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

    def maybe_auto_generate_metrics
      return unless @agent_name.present? && Metric.for_agent(@agent_name).active.none?

      begin
        auto_generate_metrics(@agent_name)
      rescue MetricSuggester::Error => e
        Rails.logger.warn("MetricSuggester failed for #{@agent_name}: #{e.message} — proceeding without auto-generated metrics")
      end
    end

    def auto_generate_metrics(agent_name)
      suggestions = MetricSuggester.call(agent_name: agent_name, model: nil)
      suggestions.each do |s|
        Metric.find_or_initialize_by(agent_name: agent_name, name: s[:name]).tap do |m|
          m.description = s[:description]
          m.weight      = s[:weight]
          m.active      = true
          m.save!
        end
      end
    end

    def create_experiment!
      Experiment.create!(
        name:              payload["experiment_name"].presence || "Manual eval",
        dataset_id:        payload["dataset_id"],
        prompt_id:         @prompt_id,
        runner_class:      "Evaluation::Runners::StubbedAgentRun",
        evaluator_classes: [ "Evaluation::Evaluators::LLMJudgeEval" ],
        metadata:          { "triggered_by" => "manual" },
        sample_model:      payload["sample_model"].presence,
        evaluation_model:  payload["evaluation_model"].presence
      )
    end
  end
end
