# frozen_string_literal: true

module Evaluation
  class ExperimentsController < ApplicationController
    before_action :set_experiment, only: [ :show, :improve, :compare, :activate ]

    def index
      @experiments = Leva::Experiment.order(created_at: :desc).includes(:prompt)
    end

    def show
      @newer_experiment = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: @experiment.prompt&.name })
        .where("leva_experiments.id > ?", @experiment.id)
        .order(id: :desc)
        .first
    end

    def improve
      new_prompt = Evaluation::PromptImprover.call(experiment: @experiment)
      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt improvement triggered. Evaluating prompt v#{new_prompt.version}…"
    rescue Evaluation::PromptImprover::Error => e
      redirect_to evaluation_experiment_path(@experiment), alert: e.message
    end

    def compare
      @candidate = Leva::Experiment.find(params[:candidate_id])
      return unless @candidate.completed?

      @result = Evaluation::Comparison.call(
        baseline_experiment: @experiment,
        candidate_experiment: @candidate
      )
    end

    def activate
      prompt = @experiment.prompt
      Leva::Prompt.where(name: prompt.name).where.not(id: prompt.id).find_each do |p|
        meta = JSON.parse(p.metadata || "{}") rescue {} # rubocop:disable Style/RescueModifier
        meta.delete("active")
        p.update!(metadata: meta.to_json)
      end
      meta = JSON.parse(prompt.metadata || "{}") rescue {} # rubocop:disable Style/RescueModifier
      meta["active"] = true
      prompt.update!(metadata: meta.to_json)
      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt v#{prompt.version} activated for #{prompt.name}."
    end

    private

    def set_experiment
      @experiment = Leva::Experiment.find(params[:id])
    end
  end
end
