module Evaluation
  class PromptCreator
    def self.call(name:, system_prompt:, user_prompt:, output_schema: nil)
      new(name:, system_prompt:, user_prompt:, output_schema:).call
    end

    def initialize(name:, system_prompt:, user_prompt:, output_schema: nil)
      @attributes = { name:, system_prompt:, user_prompt:, output_schema: }
    end

    def call
      prompt = Evaluation::Prompt.create!(**@attributes)
      Evaluation::PromptAutoEvalJob.perform_later(prompt_id: prompt.id)
      prompt
    end
  end
end
