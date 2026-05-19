# frozen_string_literal: true

module Orchestration
  class StepActionsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step

    def create
      # TODO: move out the logic to a form object
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
      mapping, key_error = parse_input_mapping
      if key_error
        redirect_to orchestration_pipeline_path(@pipeline), alert: key_error and return
      end

      result = Orchestration::InputMappingUpdater.call(step_action: @step_action, input_mapping: mapping)

      if result.saved
        notice = if result.warnings.any?
          "Mapping saved. Warning: #{result.warnings.map { |w| "#{w.code}: #{w.message}" }.join("; ")}"
        else
          "Mapping saved."
        end
        redirect_to orchestration_pipeline_path(@pipeline), notice: notice
      else
        error_summary = result.errors.map(&:message).join("; ").presence || "Invalid mapping."
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
      permitted = params.require(:orchestration_step_action).permit(input_mapping: {})
      mapping   = (permitted[:input_mapping]&.to_h || {}).deep_stringify_keys

      new_key  = params.dig(:orchestration_step_action, :new_key).presence
      new_from = params.dig(:orchestration_step_action, :new_from).presence

      if new_key
        unless new_key.match?(Orchestration::StepAction::OUTPUT_KEY_FORMAT)
          return [ {}, "Key #{new_key.inspect} is invalid: must only contain lowercase letters, digits, and underscores, and start with a letter." ]
        end
        if new_from
          new_path = params.dig(:orchestration_step_action, :new_path).presence
          mapping[new_key] = { "from" => new_from, "path" => new_path }.compact
        end
      end

      [ mapping, nil ]
    end
  end
end
