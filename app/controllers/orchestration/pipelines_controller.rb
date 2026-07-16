
module Orchestration
  class PipelinesController < ApplicationController
    include JsonParamsParsing

    before_action :set_pipeline, only: [ :show, :edit, :update, :destroy, :run, :toggle ]

    def index
      @pipelines = Orchestration::Pipeline.with_step_counts
    end

    def show
      @steps = @pipeline.steps_with_actions
      @actions = Orchestration::Action.order(:name)
      @latest_run = @pipeline.latest_run
    end
    def new
      @pipeline = Orchestration::Pipeline.new
    end

    def edit
    end
    def create
      @pipeline = Orchestration::Pipeline.new(pipeline_params)
      if @pipeline.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Pipeline created."
      else
        render :new, status: :unprocessable_content
      end
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


    def update
      if @pipeline.update(pipeline_params)
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Pipeline updated."
      else
        render :edit, status: :unprocessable_content
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
      permitted = params.expect(
        orchestration_pipeline: [ :name, :description, :enabled, :cron_expression, :model, :initial_input_schema ]
      )

      begin
        parse_json_field(permitted, :initial_input_schema)
      rescue JSON::ParserError
        permitted[:initial_input_schema] = nil
      end

      permitted
    end
  end
end
