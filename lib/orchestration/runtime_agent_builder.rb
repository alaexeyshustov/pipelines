module Orchestration
  class RuntimeAgentBuilder
    def initialize(policy:, chat: nil)
      @policy = policy
      @chat = chat
    end

    def build
      agent = base_agent
      apply_model(agent)
      apply_tools(agent)
      apply_schema(agent)
      apply_prompt(agent)
      agent
    end

    private

    def apply_model(agent)
      model = @policy.model
      agent.with_model(model) if model.present?
    end

    def apply_tools(agent)
      tools = @policy.tools
      agent.with_tools(*tools, replace: true) if tools.present?
    end

    def apply_schema(agent)
      schema = @policy.output_schema
      agent.with_schema(schema) if schema.present?
    end

    def apply_prompt(agent)
      prompt = @policy.prompt
      agent.chat.with_instructions(prompt) if prompt.present?
    end

    def base_agent
      RubyLLM::Agent.new(chat: runtime_chat)
    end

    def runtime_chat
      @chat || Chat.create!
    end
  end
end
