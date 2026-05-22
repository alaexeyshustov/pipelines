# frozen_string_literal: true

module Evaluation
  class Sampler
    WRITE_BLOCKED_SENTINEL = "[write tool blocked during sampling]"

    def self.call(experiment:, dataset_sample:, prompt:)
      new(experiment: experiment, dataset_sample: dataset_sample, prompt: prompt).call
    end

    def initialize(experiment:, dataset_sample:, prompt:)
      @experiment     = experiment
      @dataset_sample = dataset_sample
      @prompt         = prompt
    end

    def call
      agent_record = find_agent_record
      raise ArgumentError, "No agent found for experiment" unless agent_record

      action = find_action_for(agent_record)
      raise ArgumentError, "No action found for agent #{agent_record.name}" unless action

      tool_classes  = resolve_tools(agent_record)
      wrapped_tools = wrap_write_tools(tool_classes)

      policy = Orchestration::AgentResolutionPolicy.call(
        action:           action,
        tool_classes:     wrapped_tools,
        pipeline_model:   @experiment.sample_model,
        prompt_override:  @prompt&.system_prompt
      )
      agent  = Orchestration::RuntimeAgentBuilder.new(policy: policy).build
      result = agent.ask(@dataset_sample.input.to_json)

      tool_calls = capture_tool_calls(agent)
      output     = result.content.is_a?(String) ? result.content : result.content.to_json

      Sample.create!(
        experiment:     @experiment,
        dataset_sample: @dataset_sample,
        prompt:         @prompt,
        tool_calls:     tool_calls,
        output:         output
      )
    end

    private

    def find_agent_record
      agent_name = @experiment.agent_name
      return unless agent_name

      Orchestration::Agent.find_by(name: agent_name)
    end

    def find_action_for(agent_record)
      Orchestration::Action.where(kind: :agent, agent_id: agent_record.id).first
    end

    def resolve_tools(agent_record)
      configured = agent_record.tools.presence
      if configured
        return configured.map do |tool|
          namespace = tool.to_s.split("::").first
          unless Orchestration::Agent::ALLOWED_TOOL_NAMESPACES.include?(namespace)
            raise ArgumentError, "Tool '#{tool}' is outside allowed namespaces"
          end

          tool.constantize
        rescue NameError
          raise ArgumentError, "Unknown tool class: #{tool}"
        end
      end

      agent_class = agent_record.name.safe_constantize
      return agent_class.tools if agent_class.respond_to?(:tools)

      raise ArgumentError, "agent #{agent_record.name.inspect} has no configured tools"
    end

    def wrap_write_tools(tool_classes)
      tool_classes.map do |tool_class|
        next tool_class if tool_class.respond_to?(:readonly?) && tool_class.readonly? # steep:ignore

        block_write_tool(tool_class)
      end
    end

    def block_write_tool(tool_class)
      sentinel = WRITE_BLOCKED_SENTINEL
      # steep:ignore:start
      Class.new(tool_class) do
        define_method(:execute) do |**kwargs|
          Rails.logger.info("Sampler: blocked write tool #{name} (#{kwargs.keys.inspect})")
          sentinel
        end
      end
      # steep:ignore:end
    end

    def capture_tool_calls(agent)
      # steep:ignore:start
      agent.messages
           .where(role: "tool")
           .order(:id)
           .includes(:parent_tool_call)
           .filter_map do |msg|
             tc = msg.parent_tool_call
             next unless tc

             { tool_name: tc.name, arguments: tc.arguments, result: msg.content }
           end
      # steep:ignore:end
    end
  end
end
