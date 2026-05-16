module Orchestration
  class RuntimeAgentBuilder
    def initialize(action:, chat: nil, pipeline_model: nil, prompt_override: nil, step_params: nil, tool_classes: nil)
      @action = action
      @chat = chat
      @pipeline_model = pipeline_model
      @prompt_override = prompt_override
      @step_params = step_params || {}
      @tool_classes = tool_classes
    end

    def build
      agent = base_agent
      agent.with_model(resolved_model) if resolved_model.present?

      tools = resolved_tools
      agent.with_tools(*tools, replace: true) if tools.present?

      schema = resolved_generation_schema
      agent.with_schema(schema) if schema.present?

      prompt = resolved_prompt
      agent.chat.with_instructions(prompt) if prompt.present?
      agent
    end

    def resolved_output_schema
      agent_record.output_schema.presence || @action.output_schema
    end

    def resolved_params
      base_params = agent_record.params.presence || @action.params || {}
      base_params.merge(@step_params || {})
    end

    def snapshot
      {
        model: resolved_model,
        prompt: resolved_prompt,
        tools: resolved_tools&.map(&:to_s) || [],
        params: resolved_params,
        output_schema: resolved_output_schema
      }
    end

    private

    def base_agent
      # steep:ignore:start
      RubyLLM::Agent.new(chat: runtime_chat)
      # steep:ignore:end
    end

    def runtime_chat
      @chat || Chat.create!
    end

    def agent_record
      @action.agent || raise(ArgumentError, "No agent associated with action #{@action.id}")
    end

    def resolved_model
      @pipeline_model.presence || agent_record.model.presence || @action.model
    end

    def resolved_prompt
      @prompt_override.presence || agent_record.prompt.presence || @action.prompt
    end

    def resolved_tools
      return @tool_classes if @tool_classes.present?

      configured_tools = agent_record.tools.presence || @action.tools
      configured_tools&.map do |tool|
        next tool if tool.is_a?(Class)

        namespace = tool.to_s.split("::").first
        unless Orchestration::Agent::ALLOWED_TOOL_NAMESPACES.include?(namespace)
          raise ArgumentError, "Tool '#{tool}' is outside allowed namespaces (#{Orchestration::Agent::ALLOWED_TOOL_NAMESPACES.join(', ')})"
        end

        tool.constantize
      rescue NameError
        raise ArgumentError, "Unknown tool class: #{tool}"
      end
    end

    def resolved_generation_schema
      return agent_record.output_schema if agent_record.output_schema.present?
      return @action.schema_class.constantize if @action.schema_class.present?

      nil
    end
  end
end
