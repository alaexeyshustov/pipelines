# frozen_string_literal: true

module Orchestration
  class ActionsController < ApplicationController
    before_action :set_action, only: [ :edit, :update, :destroy ]

    def index
      @actions = Orchestration::Action
        .left_joins(step_actions: { step: :pipeline })
        .select("actions.*, COUNT(DISTINCT pipelines.id) AS pipeline_count")
        .group("actions.id")
        .order("actions.name")
    end

    def new
      @action = Orchestration::Action.new
    end

    def create
      @action = Orchestration::Action.new(action_params)
      if @action.save
        redirect_to orchestration_actions_path, notice: "Action created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @action.update(action_params)
        redirect_to orchestration_actions_path, notice: "Action updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @action.destroy
      if @action.errors.any?
        redirect_to orchestration_actions_path, alert: "Cannot delete action: #{@action.errors.full_messages.to_sentence}."
      else
        redirect_to orchestration_actions_path, notice: "Action deleted."
      end
    end

    private

    def set_action
      @action = Orchestration::Action.find(params[:id])
    end

    def action_params
      parsed = params.require(:orchestration_action).permit(
        :name, :description, :agent_class, :model, :tools, :prompt, :params
      )
      parsed[:tools] = JSON.parse(parsed[:tools]) if parsed[:tools].present?
      parsed[:params] = JSON.parse(parsed[:params]) if parsed[:params].present?
      parsed
    rescue JSON::ParserError => e
      params.require(:orchestration_action).permit(:name, :description, :agent_class, :model, :tools, :prompt, :params)
    end
  end
end
