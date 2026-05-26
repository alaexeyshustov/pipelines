# frozen_string_literal: true

module Orchestration
  class StepActionsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step

    def create
      form = Orchestration::StepActionCreateForm.new(
        step: @step,
        action_id: params.dig(:orchestration_step_action, :action_id)
      )

      if form.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Action attached."
      else
        redirect_to orchestration_pipeline_path(@pipeline), alert: form.errors.full_messages.first || "Could not attach action."
      end
    end

    def update
      @step_action = @step.step_actions.find(params[:id])
      sa_params = params[:orchestration_step_action]
      form = Orchestration::InputMappingForm.new(
        step_action: @step_action,
        input_mapping: sa_params&.[](:input_mapping),
        new_key:  sa_params&.dig(:new_key),
        new_from: sa_params&.dig(:new_from),
        new_path: sa_params&.dig(:new_path)
      )

      if form.save
        result = form.result
        notice = if result.warnings.any?
          "Mapping saved. Warning: #{result.warnings.map { |w| "#{w.code}: #{w.message}" }.join("; ")}"
        else
          "Mapping saved."
        end
        redirect_to orchestration_pipeline_path(@pipeline), notice: notice
      else
        error_summary = if form.result
          form.result.errors.map(&:message).join("; ").presence || "Invalid mapping."
        else
          form.errors.full_messages.first || "Invalid mapping."
        end
        redirect_to orchestration_pipeline_path(@pipeline), alert: error_summary
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
  end
end
