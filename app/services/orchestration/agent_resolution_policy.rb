module Orchestration
  class AgentResolutionPolicy
    Result = Data.define(:model, :prompt, :tools, :params, :output_schema)

    def self.call(action:, pipeline_model: nil, prompt_override: nil, step_params: nil, tool_classes: nil)
      new(action:, pipeline_model:, prompt_override:, step_params:, tool_classes:).call
    end

    def initialize(action:, pipeline_model: nil, prompt_override: nil, step_params: nil, tool_classes: nil)
      @action = action
      @pipeline_model = pipeline_model
      @prompt_override = prompt_override
      @step_params = step_params || {}
      @tool_classes = tool_classes
    end

    def call
      Result.new(
        model: resolved_model,
        prompt: resolved_prompt,
        tools: resolved_tools,
        params: resolved_params,
        output_schema: resolved_output_schema
      )
    end

    private

    def agent_record
      @action.agent || raise(ArgumentError, "No agent associated with action #{@action.id}")
    end

    def resolved_model
      @pipeline_model.presence || agent_record.model
    end

    def resolved_prompt
      @prompt_override.presence || agent_record.prompt
    end

    def resolved_tools
      return @tool_classes if @tool_classes.present?

      configured_tools = agent_record.tools
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

    def resolved_params
      normalized_hash(agent_record.params, field_name: "agent params")
        .merge(normalized_hash(@step_params, field_name: "step params"))
    end

    def resolved_output_schema
      agent_record.output_schema.presence
    end

    def normalized_hash(value, field_name:)
      return {} if value.nil?

      parsed =
        case value
        when Hash
          value
        when String
          return {} if value.blank?

          JSON.parse(value)
        else
          raise ArgumentError, "#{field_name} must be a Hash or JSON object string, got #{value.class}"
        end

      return parsed.transform_keys(&:to_s) if parsed.is_a?(Hash)

      raise ArgumentError, "#{field_name} must be a JSON object, got #{parsed.class}"
    rescue JSON::ParserError => e
      raise ArgumentError, "#{field_name} must be valid JSON: #{e.message}"
    end
  end
end
