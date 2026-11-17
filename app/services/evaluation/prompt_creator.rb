module Evaluation
  class PromptCreator
    Result = Data.define(:prompt)

    def self.call(name:, system_prompt:, user_prompt:, output_schema: nil)
      new(name:, system_prompt:, user_prompt:, output_schema:).call
    end

    def initialize(name:, system_prompt:, user_prompt:, output_schema: nil)
      @attributes = { name:, system_prompt:, user_prompt:, output_schema: }
    end

    def call
      prompt = Evaluation::Prompt.create!(**@attributes)
      Evaluation::PromptAutoEvalJob.perform_later(prompt_id: prompt.id)
      Result.new(prompt:)
    end
  end
end
