module Orchestration
  class RuntimeAgentBuilder
    def initialize(policy:, chat: nil)
      @policy = policy
      @chat = chat
    end

    def build
      agent = base_agent
      model = @policy.model
      agent.with_model(model) unless model.nil? || model.empty?

      tools = @policy.tools
      agent.with_tools(*tools, replace: true) if tools.present?

      schema = @policy.output_schema
      agent.with_schema(schema) if schema.present?

      prompt = @policy.prompt
      agent.chat.with_instructions(prompt) unless prompt.nil? || prompt.empty?
      agent
    end

    private

    def base_agent
      RubyLLM::Agent.new(chat: runtime_chat)
    end

    def runtime_chat
      @chat || Chat.create!
    end
  end
end
