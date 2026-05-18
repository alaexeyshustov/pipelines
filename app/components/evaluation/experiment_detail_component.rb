# frozen_string_literal: true

module Evaluation
  class ExperimentDetailComponent < ViewComponent::Base
    def initialize(experiment:)
      @experiment = experiment
    end

    def agent_name
      @agent_name ||= @experiment.prompt&.name
    end

    def metrics
      @metrics ||= agent_name ? Metric.for_agent(agent_name).order(:name) : Evaluation::Metric.none
    end

    def runner_result_count
      @runner_result_count ||= @experiment.runner_results.count
    end

    def per_metric_avg
      @per_metric_avg ||= EvaluationResult.per_metric_averages(@experiment)
    end

    def runner_model
      @runner_model ||= begin
        meta = @experiment.metadata || {}
        agent = agent_name ? Orchestration::Agent.find_by(name: agent_name) : nil
        meta["pipeline_model"].presence || agent&.model.presence
      end
    end

    def judge_model
      @judge_model ||= Evaluators::LLMJudgeEval.judge_model
    end

    def newer_experiment
      @newer_experiment ||= begin
        return unless @experiment.prompt

        Experiment
          .joins(:prompt)
          .where(evaluation_prompts: { name: @experiment.prompt.name })
          .where("evaluation_experiments.id > ?", @experiment.id)
          .order(id: :desc)
          .includes(:prompt)
          .first
      end
    end
  end
end
