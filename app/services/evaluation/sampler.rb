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

      resolved_action = find_action_for!(agent_record)
      agent  = build_agent(resolved_action, agent_record)
      result = agent.ask(@dataset_sample.input.to_json)
      persist_sample(agent, result)
    end

    private

    def build_agent(resolved_action, agent_record)
      tool_classes  = Orchestration::ToolResolver.new(agent: agent_record).resolve
      wrapped_tools = wrap_write_tools(tool_classes)
      policy = Orchestration::AgentResolutionPolicy.new(
        action:          resolved_action,
        tool_classes:    wrapped_tools, # steep:ignore
        pipeline_model:  @experiment.sample_model,
        prompt_override: @prompt&.system_prompt
      ).resolve
      Orchestration::RuntimeAgentBuilder.new(policy:).build
    end

    def persist_sample(agent, result)
      tool_calls = capture_tool_calls(agent)
      output     = result.content.is_a?(String) ? result.content : result.content.to_json
      Evaluation::Sample.create!(
        experiment_id:     @experiment.id,
        dataset_sample_id: @dataset_sample.id,
        prompt_id:         @prompt&.id,
        tool_calls:        tool_calls,
        output:            output
      )
    end

    def find_agent_record
      agent_name = @experiment.agent_name
      return unless agent_name

      Orchestration::Agent.find_by(name: agent_name)
    end

    def find_action_for(agent_record)
      Orchestration::Action.where(kind: :agent, agent_id: agent_record.id).first
    end

    def find_action_for!(agent_record)
      action = find_action_for(agent_record)
      if action.nil?
        raise ArgumentError, "No action found for agent #{agent_record.name}"
      else
        action
      end
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
      end # : singleton(RubyLLM::Tool)
      # steep:ignore:end
    end

    def capture_tool_calls(agent)
      agent_messages(agent).filter_map do |msg|
        tc = msg.parent_tool_call # : ToolCall?
        next unless tc

        {
          "tool_name" => tc.name,
          "arguments" => tc.arguments,
          "result" => msg.content.to_s
        }
      end
    end

    def agent_messages(agent)
      agent.messages.where(role: "tool").order(:id).includes(:parent_tool_call).to_a
    end
  end
end
