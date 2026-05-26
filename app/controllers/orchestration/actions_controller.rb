# frozen_string_literal: true

module Orchestration
  class ActionsController < ApplicationController
    before_action :set_action, only: [ :edit, :update, :destroy ]
    before_action :load_agents, only: [ :new, :create, :edit, :update ]

    def index
      @actions = Orchestration::Action
        .includes(:agent)
        .left_joins(step_actions: { step: :pipeline })
        .select("orchestration_actions.*, COUNT(DISTINCT orchestration_pipelines.id) AS pipeline_count")
        .group("orchestration_actions.id")
        .order("orchestration_actions.name")
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
      errors = @action.errors
      if errors.any?
        redirect_to orchestration_actions_path, alert: "Cannot delete action: #{errors.full_messages.to_sentence}."
      else
        redirect_to orchestration_actions_path, notice: "Action deleted."
      end
    end

    private

    def set_action
      @action = Orchestration::Action.find(params[:id])
    end

    def load_agents
      enabled = Orchestration::Agent.enabled
      @agents = if @action&.agent_id && !enabled.exists?(@action.agent_id)
        enabled.or(Orchestration::Agent.where(id: @action.agent_id)).order(:name)
      else
        enabled.order(:name)
      end
    end

    def action_params
      params.require(:orchestration_action).permit(
        :name, :description, :kind, :agent_id, :agent_class
      )
    end
  end
end
