module Orchestration
  class PipelineExporter
    FORMAT = "pipeline_export".freeze
    SCHEMA_VERSION = 1

    PRELOAD = { steps: { step_actions: { action: :agent } } }.freeze

    def self.call(pipelines)
      new(pipelines).call
    end

    def initialize(pipelines)
      @pipelines = pipelines.to_a
    end

    def call
      ActiveRecord::Associations::Preloader.new(records: @pipelines, associations: PRELOAD).call
      {
        "format" => FORMAT,
        "schema_version" => SCHEMA_VERSION,
        "pipelines" => @pipelines.map { |pipeline| export_pipeline(pipeline) }
      }
    end

    private

    def export_pipeline(pipeline)
      {
        "name" => pipeline.name,
        "description" => pipeline.description,
        "enabled" => pipeline.enabled,
        "cron_expression" => pipeline.cron_expression,
        "model" => pipeline.model,
        "initial_input_schema" => pipeline.initial_input_schema,
        "steps" => pipeline.steps.map { |step| export_step(step) }
      }
    end

    def export_step(step)
      {
        "name" => step.name,
        "enabled" => step.enabled,
        "step_actions" => step.step_actions.map { |step_action| export_step_action(step_action) }
      }
    end

    def export_step_action(step_action)
      {
        "output_key" => step_action.output_key,
        "input_mapping" => step_action.input_mapping,
        "action" => export_action(step_action.action)
      }
    end

    def export_action(action)
      agent_class = action.agent_class
      agent = action.agent
      {
        "name" => action.name,
        "description" => action.description,
        "kind" => action.kind,
        "agent_class" => agent_class.present? ? AgentClassKeyword.encode(agent_class.to_s) : nil,
        "agent" => agent && export_agent(agent)
      }
    end

    def export_agent(agent)
      {
        "name" => agent.name,
        "description" => agent.description,
        "model" => agent.model,
        "tools" => agent.tools,
        "enabled" => agent.enabled,
        "prompt" => agent.prompt,
        "output_schema" => agent.output_schema,
        "input_schema" => agent.input_schema
      }
    end
  end
end
