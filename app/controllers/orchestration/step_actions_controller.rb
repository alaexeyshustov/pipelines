# frozen_string_literal: true

module Orchestration
  class StepActionsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step

    def create
      action = Orchestration::Action.find_by(id: params.dig(:orchestration_step_action, :action_id))
      unless action
        redirect_to orchestration_pipeline_path(@pipeline), alert: "Invalid action." and return
      end

      parsed = step_action_params
      unless parsed
        redirect_to orchestration_pipeline_path(@pipeline), alert: "Params must be valid JSON." and return
      end

      next_position = (@step.step_actions.maximum(:position) || 0) + 1
      key = Orchestration::OutputKeyDeriver.call(action_name: action.name, step: @step)
      @step_action = @step.step_actions.build(parsed.merge(position: next_position, output_key: key))

      begin
        saved = @step_action.save
      rescue ActiveRecord::RecordNotUnique
        @step_action.output_key = "#{key}_#{SecureRandom.hex(3)}"
        saved = @step_action.save
      end

      if saved
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Action attached."
      else
        redirect_to orchestration_pipeline_path(@pipeline), alert: "Could not attach action."
      end
    end

    def update
      @step_action = @step.step_actions.find(params[:id])
      new_mapping = parse_input_mapping

      result = nil
      saved = false

      ActiveRecord::Base.transaction do
        @step_action.update!(input_mapping: new_mapping)
        validator_results = Orchestration::Pipeline::Validator.call(@pipeline)
        result = validator_results.find { |r| r.step_action_id == @step_action.id }

        if result&.errors&.any?
          raise ActiveRecord::Rollback
        end

        saved = true
      end

      if saved
        if result&.warnings&.any?
          warning_summary = result.warnings.map { |w| "#{w.code}: #{w.message}" }.join("; ")
          redirect_to orchestration_pipeline_path(@pipeline),
                      notice: "Mapping saved. Warning: #{warning_summary}"
        else
          redirect_to orchestration_pipeline_path(@pipeline), notice: "Mapping saved."
        end
      else
        error_summary = result&.errors&.map(&:message)&.join("; ") || "Invalid mapping."
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

    def step_action_params
      permitted = params.require(:orchestration_step_action).permit(:action_id, :params)
      raw = permitted[:params]
      permitted[:params] = JSON.parse(raw) if raw.present?
      permitted
    rescue JSON::ParserError
      nil
    end

    def parse_input_mapping
      raw = params.dig(:orchestration_step_action, :input_mapping)
      mapping = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.deep_stringify_keys : {}

      new_key  = params.dig(:orchestration_step_action, :new_key).presence
      new_from = params.dig(:orchestration_step_action, :new_from).presence
      if new_key && new_from
        new_path = params.dig(:orchestration_step_action, :new_path).presence
        mapping[new_key] = { "from" => new_from, "path" => new_path }.compact
      end

      mapping
    end
  end
end
