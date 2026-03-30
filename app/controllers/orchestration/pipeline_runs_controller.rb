# frozen_string_literal: true

module Orchestration
  class PipelineRunsController < ApplicationController
    before_action :set_pipeline

    def index
      @pagy, @runs = pagy(:offset, @pipeline.pipeline_runs.order(created_at: :desc))
    end

    def show
      @run = @pipeline.pipeline_runs.find(params[:id])
      action_runs_by_step = @run.action_runs
        .includes(step_action: :action)
        .group_by { |ar| ar.step_action.step_id }
      @steps_with_action_runs = @pipeline.steps.map do |step|
        action_runs = action_runs_by_step.fetch(step.id, [])
        { step: step, action_runs: action_runs, derived_status: Orchestration::Step.derive_status(action_runs) }
      end
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.includes(:steps).find(params[:pipeline_id])
    end
  end
end
