# frozen_string_literal: true

module Orchestration
  class AgentsController < ApplicationController
    include JsonParamsParsing

    before_action :set_agent, only: [ :show, :edit, :update, :destroy, :toggle ]

    def index
      @agents = Orchestration::Agent
        .left_joins(:actions)
        .select("orchestration_agents.*, COUNT(DISTINCT orchestration_actions.id) AS action_count")
        .group("orchestration_agents.id")
        .order("orchestration_agents.name")
    end

    def show
      @using_actions = @agent.actions.includes(step_actions: { step: :pipeline }).order(:name)
    end

    def new
      @agent = Orchestration::Agent.new
    end

    def edit
    end
    def create
      @agent = Orchestration::Agent.new(agent_params)
      if @agent.save
        redirect_to orchestration_agents_path, notice: "Agent created."
      else
        render :new, status: :unprocessable_content
      end
    end


    def update
      if @agent.update(agent_params)
        redirect_to orchestration_agents_path, notice: "Agent updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @agent.destroy!
      redirect_to orchestration_agents_path, notice: "Agent deleted."
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to orchestration_agents_path, alert: "Cannot delete agent: it is referenced by one or more actions."
    end

    def toggle
      @agent.with_lock do
        @agent.update(enabled: !@agent.enabled)
      end
      redirect_to orchestration_agents_path, notice: "Agent #{@agent.enabled? ? "enabled" : "disabled"}."
    end

    private

    def set_agent
      @agent = Orchestration::Agent.find(params[:id])
    end

    def agent_params
      permitted = params.expect(
        orchestration_agent: [ :name, :description, :model, :prompt, :output_schema, tools: [] ]
      )

      permitted[:tools] = Array(permitted[:tools]).compact_blank if permitted.key?(:tools)

      begin
        parse_json_field(permitted, :output_schema)
      rescue JSON::ParserError
        permitted[:output_schema] = nil
      end

      permitted
    end
  end
end
