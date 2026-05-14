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
        .order(:id)
        .group_by { |ar| ar.step_action.step_id }

      accumulated_outputs = { "_initial" => @run.initial_input }.compact

      @steps_with_action_runs = @pipeline.steps.map do |step|
        available_outputs = accumulated_outputs.dup
        action_runs = action_runs_by_step.fetch(step.id, [])
        action_runs.each { |ar| accumulated_outputs[ar.step_action.output_key] = ar.output || {} }
        {
          step: step,
          action_runs: action_runs,
          derived_status: Orchestration::Step.derive_status(action_runs),
          available_outputs: available_outputs
        }
      end
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.includes(:steps).find(params[:pipeline_id])
    end
  end
end
