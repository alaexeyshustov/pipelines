
module Orchestration
  class PipelineRunsController < ApplicationController
    before_action :set_pipeline

    def index
      @pagy, @runs = pagy(:offset, @pipeline.pipeline_runs.recent_first)
    end

    def show
      @run = @pipeline.pipeline_runs.find(params[:id])
      @action_runs_by_step = @run.action_runs
        .includes(step_action: :action)
        .order(:id)
        .group_by { |ar| ar.step_action.step_id }
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.includes(:steps).find(params[:pipeline_id])
    end
  end
end
