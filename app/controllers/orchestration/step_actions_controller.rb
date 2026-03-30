# frozen_string_literal: true

module Orchestration
  class StepActionsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step

    def create
      next_position = (@step.step_actions.maximum(:position) || 0) + 1
      @step_action = @step.step_actions.build(step_action_params.merge(position: next_position))
      if @step_action.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Action attached."
      else
        redirect_to orchestration_pipeline_path(@pipeline), alert: "Could not attach action."
      end
    end

    def destroy
      @step_action = @step.step_actions.find(params[:id])
      @step_action.destroy
      redirect_to orchestration_pipeline_path(@pipeline), notice: "Action detached."
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.find(params[:pipeline_id])
    end

    def set_step
      @step = @pipeline.steps.find(params[:step_id])
    end

    def step_action_params
      parsed = params.require(:orchestration_step_action).permit(:action_id, :params)
      if parsed[:params].present?
        parsed[:params] = JSON.parse(parsed[:params])
      end
      parsed
    rescue JSON::ParserError
      params.require(:orchestration_step_action).permit(:action_id, :params)
    end
  end
end
