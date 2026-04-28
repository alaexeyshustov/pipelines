module Evaluation
  class MetricExtractor
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an evaluation expert. Given an agent's instructions, identify evaluable behaviors and return candidate metrics as a JSON array.
      Each metric must have a "name" (snake_case, concise) and a "description" (rubric text explaining what to measure and how to score).
      Return ONLY the JSON array with no additional text.
    PROMPT

    def initialize(agent_name)
      @agent_name = agent_name
    end

    def call
      prompt = Leva::Prompt.find_by(name: @agent_name)
      raise ArgumentError, "No prompt found for agent: #{@agent_name}" if prompt.nil?

      response = RubyLLM.chat(model: "claude-sonnet-4-6")
                        .with_instructions(SYSTEM_PROMPT)
                        .ask("Agent instructions:\n\n#{prompt.system_prompt}")

      JSON.parse(response.content)
    end
  end
end
