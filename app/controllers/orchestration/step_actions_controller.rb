# frozen_string_literal: true

module Orchestration
  class StepActionsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step

    def create
      next_position = (@step.step_actions.maximum(:position) || 0) + 1
      action = Orchestration::Action.find_by(id: step_action_params[:action_id])
      key = action ? derive_output_key(action.name) : "action_#{next_position}"
      attrs = step_action_params.merge(position: next_position, output_key: key)
      @step_action = @step.step_actions.build(attrs)
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
      permitted = params.require(:orchestration_step_action).permit(:action_id, :params)
      raw = permitted[:params]
      permitted[:params] = JSON.parse(raw) if raw.present?
      permitted
    rescue JSON::ParserError
      permitted
    end

    def derive_output_key(action_name)
      base = action_name.to_s.parameterize(separator: "_")
      base = "action" if base.blank?
      base = "x_#{base}" unless base.match?(/\A[a-z]/)

      candidate = base
      suffix    = 2
      while @step.step_actions.exists?(output_key: candidate)
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end
      candidate
    end
  end
end
