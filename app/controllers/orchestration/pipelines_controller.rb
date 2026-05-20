# frozen_string_literal: true

module Orchestration
  class PipelinesController < ApplicationController
    before_action :set_pipeline, only: [ :show, :edit, :update, :destroy, :run, :toggle ]

    def index
      @pipelines = Orchestration::Pipeline
        .left_joins(:steps)
        .select("orchestration_pipelines.*, COUNT(orchestration_steps.id) AS step_count")
        .group("orchestration_pipelines.id")
        .order("orchestration_pipelines.name")
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
      @steps = @pipeline.steps.includes(step_actions: { action: :agent })
      @actions = Orchestration::Action.order(:name)
      @latest_run = @pipeline.pipeline_runs.order(created_at: :desc).first
    end

    def run
      form = Orchestration::PipelineRunForm.new(pipeline: @pipeline, initial_input_params: params[:initial_input])
      path = orchestration_pipeline_path(@pipeline)

      if form.save
        PipelineRunJob.perform_later(form.pipeline_run.id)
        redirect_to path, notice: "Pipeline run triggered."
      else
        redirect_to path, alert: form.errors.full_messages.first || "Failed to trigger pipeline run."
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
      params.require(:orchestration_pipeline).permit(:name, :description, :enabled, :cron_expression, :model)
    end
  end
end
