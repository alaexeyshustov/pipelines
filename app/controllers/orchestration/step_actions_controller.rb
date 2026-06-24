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
      form = build_input_mapping_form
      if form.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: build_notice_message(form.result)
      else
        redirect_to orchestration_pipeline_path(@pipeline), alert: build_error_summary(form)
      end
    end

    def destroy
      @step_action = @step.step_actions.find(params[:id])
      @step_action.destroy
      redirect_to orchestration_pipeline_path(@pipeline), notice: "Action detached."
    end

    private

    def build_input_mapping_form
      sa_params = params[:orchestration_step_action]
      Orchestration::InputMappingForm.new(
        step_action:   @step_action,
        input_mapping: sa_params&.[](:input_mapping),
        new_key:       sa_params&.dig(:new_key),
        new_from:      sa_params&.dig(:new_from),
        new_path:      sa_params&.dig(:new_path)
      )
    end

    def build_notice_message(result)
      if result&.warnings&.any?
        "Mapping saved. Warning: #{result.warnings.map { |w| "#{w.code}: #{w.message}" }.join("; ")}"
      else
        "Mapping saved."
      end
    end

    def build_error_summary(form)
      if form.result
        form.result.errors.map(&:message).join("; ").presence || "Invalid mapping."
      else
        form.errors.full_messages.first || "Invalid mapping."
      end
    end

    def set_pipeline
      @pipeline = Orchestration::Pipeline.find(params[:pipeline_id])
    end

    def set_step
      @step = @pipeline.steps.find(params[:step_id])
    end
  end
end
