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
      @upstream_schemas_per_step = compute_upstream_schemas_per_step
      @validator_results_per_step = compute_validator_results_per_step
    end

    def run
      path = orchestration_pipeline_path(@pipeline)
      runs = @pipeline.pipeline_runs

      if runs.exists?(status: %w[pending running])
        redirect_to path, alert: "A run is already pending."
        return
      end

      initial_input = extract_initial_input
      if @pipeline.initial_input_schema.present?
        begin
          Orchestration::SchemaValidator.new(@pipeline.initial_input_schema).validate!(initial_input)
        rescue Orchestration::SchemaValidator::Error => e
          redirect_to path, alert: e.message
          return
        end
      end

      pipeline_run = runs.create(status: "pending", triggered_by: "manual", initial_input: initial_input)
      if pipeline_run.persisted?
        PipelineRunJob.perform_later(pipeline_run.id)
        redirect_to path, notice: "Pipeline run triggered."
      else
        redirect_to path, alert: "Failed to trigger pipeline run."
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

    def compute_upstream_schemas_per_step
      seen = { "_initial" => @pipeline.initial_input_schema }
      @steps.each_with_object({}) do |step, result|
        result[step.id] = seen.dup
        step.step_actions.sort_by(&:position).each do |sa|
          seen[sa.output_key] = sa.action.output_schema
        end
      end
    end

    def compute_validator_results_per_step
      all_results = Orchestration::Pipeline::Validator.call(@pipeline)
      step_action_id_to_step_id = @steps.each_with_object({}) do |step, map|
        step.step_actions.each { |sa| map[sa.id] = step.id }
      end
      all_results.each_with_object(Hash.new { |h, k| h[k] = [] }) do |result, map|
        step_id = step_action_id_to_step_id[result.step_action_id]
        map[step_id] << result if step_id
      end
    end

    def pipeline_params
      params.require(:orchestration_pipeline).permit(:name, :description, :enabled, :cron_expression, :model)
    end

    def extract_initial_input
      return nil if @pipeline.initial_input_schema.blank?

      params[:initial_input].to_unsafe_h.deep_stringify_keys
    end
  end
end
