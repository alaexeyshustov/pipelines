# frozen_string_literal: true

module Orchestration
  class PipelineRunsController < ApplicationController
    before_action :set_pipeline

    def index
      @runs = @pipeline.pipeline_runs.order(created_at: :desc)
    end

    def show
      @run = @pipeline.pipeline_runs.find(params[:id])
      action_runs_by_step = @run.action_runs
        .includes(step_action: :action)
        .group_by { |ar| ar.step_action.step_id }
      @steps_with_action_runs = @pipeline.steps.order(:position).map do |step|
        action_runs = action_runs_by_step.fetch(step.id, [])
        { step: step, action_runs: action_runs, derived_status: derive_status(action_runs) }
      end
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.find(params[:pipeline_id])
    end

    def derive_status(action_runs)
      return "pending" if action_runs.empty?
      return "failed" if action_runs.any? { |ar| ar.status == "failed" }
      return "running" if action_runs.any? { |ar| ar.status == "running" }
      return "completed" if action_runs.all? { |ar| ar.status == "completed" }

      "pending"
    end
  end
end
