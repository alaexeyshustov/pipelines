module Orchestration
  class RuntimeAgentBuilder
    def initialize(policy:, chat: nil)
      @policy = policy
      @chat = chat
    end

    def build
      agent = base_agent
      agent.with_model(@policy.model) if @policy.model.present?

      tools = @policy.tools
      agent.with_tools(*tools, replace: true) if tools.present?

      schema = @policy.output_schema
      agent.with_schema(schema) if schema.present?

      prompt = @policy.prompt
      agent.chat.with_instructions(prompt) if prompt.present?
      agent
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
  end
end
