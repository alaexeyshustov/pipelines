# frozen_string_literal: true

module Orchestration
  class PipelinesController < ApplicationController
    before_action :set_pipeline, only: [ :show, :edit, :update, :destroy, :run, :toggle ]

    def index
      @pipelines = Orchestration::Pipeline
        .left_joins(:steps)
        .select("pipelines.*, COUNT(steps.id) AS step_count")
        .group("pipelines.id")
        .order("pipelines.name")
    end

    def new
      @pipeline = Orchestration::Pipeline.new
    end

    def create
      @pipeline = Orchestration::Pipeline.new(pipeline_params)
      if @pipeline.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Pipeline created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @steps = @pipeline.steps.includes(step_actions: :action)
      @actions = Orchestration::Action.order(:name)
      @latest_run = @pipeline.pipeline_runs.order(created_at: :desc).first
    end

    def run
      if @pipeline.pipeline_runs.exists?(status: %w[pending running])
        redirect_to orchestration_pipeline_path(@pipeline), alert: "A run is already pending."
        return
      end

      pipeline_run = @pipeline.pipeline_runs.create(status: "pending", triggered_by: "manual")
      if pipeline_run.persisted?
        PipelineRunJob.perform_later(pipeline_run.id)
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Pipeline run triggered."
      else
        redirect_to orchestration_pipeline_path(@pipeline), alert: "Failed to trigger pipeline run."
      end
    end

    def toggle
      @pipeline.update!(enabled: !@pipeline.enabled)
      redirect_to request.referer || orchestration_pipeline_path(@pipeline),
                  notice: "Pipeline #{@pipeline.enabled? ? 'enabled' : 'disabled'}."
    end

    def edit
    end

    def update
      if @pipeline.update(pipeline_params)
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Pipeline updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @pipeline.destroy
      redirect_to orchestration_pipelines_path, notice: "Pipeline deleted."
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.find(params[:id])
    end

    def pipeline_params
      params.require(:orchestration_pipeline).permit(:name, :description, :enabled, :cron_expression)
    end
  end
end
