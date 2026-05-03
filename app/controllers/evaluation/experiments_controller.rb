# frozen_string_literal: true

module Evaluation
  class ExperimentsController < ApplicationController
    before_action :set_experiment, only: [ :show, :improve, :compare, :activate ]

    def index
      @experiments = Leva::Experiment.order(created_at: :desc).includes(:prompt)
    end

    def show
      return unless @experiment.prompt

      @newer_experiment = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: @experiment.prompt.name })
        .where("leva_experiments.id > ?", @experiment.id)
        .order(id: :desc)
        .includes(:prompt)
        .first
    end

    def improve
      unless @experiment.prompt
        return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt."
      end

      new_prompt = Evaluation::PromptImprover.call(experiment: @experiment)
      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt improvement triggered. Evaluating prompt v#{new_prompt.version}…"
    rescue Evaluation::PromptImprover::Error => e
      logger.error("PromptImprover failed for experiment #{@experiment.id}: #{e.message}")
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    rescue ArgumentError => e
      logger.error("PromptImprover argument error for experiment #{@experiment.id}: #{e.message}")
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    end

    def compare
      @candidate = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: @experiment.prompt&.name })
        .where.not(id: @experiment.id)
        .find_by(id: params[:candidate_id])

      unless @candidate
        return redirect_to evaluation_experiment_path(@experiment), alert: "Candidate experiment not found."
      end

      return unless @candidate.completed?

      @result = Evaluation::Comparison.call(
        baseline_experiment: @experiment,
        candidate_experiment: @candidate
      )
    end

    def activate
      prompt = @experiment.prompt
      unless prompt
        return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt."
      end

      Orchestration::Prompt.transaction do
        Orchestration::Prompt.where(name: prompt.name).where.not(id: prompt.id).find_each do |p|
          meta = begin
            JSON.parse(p.metadata || "{}")
          rescue JSON::ParserError => e
            logger.warn("Could not parse metadata for prompt #{p.id}: #{e.message}")
            next
          end
          meta.delete("active")
          p.update!(metadata: meta.to_json)
        end

        meta = begin
          JSON.parse(prompt.metadata || "{}")
        rescue JSON::ParserError => e
          logger.warn("Could not parse metadata for prompt #{prompt.id}: #{e.message}")
          raise ActiveRecord::Rollback
        end
        meta["active"] = true
        prompt.update!(metadata: meta.to_json)
      end

      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt v#{prompt.version} activated for #{prompt.name}."
    end

    private

    def set_experiment
      @experiment = Leva::Experiment.find(params[:id])
    end
  end
end
