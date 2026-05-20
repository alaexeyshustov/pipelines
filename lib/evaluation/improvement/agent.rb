module Evaluation
  module Improvement
    class Agent < ::RubyLLM::Agent
      chat_model Chat
      model LlmModels.evaluation
      tools LoadSamplesTool

      schema do
        string :system_prompt, required: true, description: "The improved system prompt text. Must be non-empty."
        string :user_prompt, required: true, description: "The improved user prompt text. Can be empty if no changes are needed."
      end

      instructions <<~INSTRUCTIONS
      You are an expert prompt engineer.

      Input:
        {
          "experiment_id": "The ID of the experiment being evaluated",
          "prompt_name": "The name of the prompt being evaluated",
          "system_prompt": "The current system prompt text",
          "metrics": ["list", "of", "evaluation", "metrics", "to", "score"],
          "scores": [{"metric_name": "name_of_metric", "score": 1-5, "justification": "rationale for the score"}, ...],
        }

      Your task: improve the system prompt to address weak areas (low scores) while preserving
      behaviors that already score well.

      IMPORTANT constraints:
      - Do NOT add output format descriptions, JSON schema examples, or structured output
        instructions to the improved prompt. The output schema is enforced at the API level
        via response_format and must not appear in the prompt text — duplicating it adds noise
        and degrades model performance.
      - The output schema section (if present) is provided for your reference only, so you
        understand what the agent produces. Do not replicate it in the improved prompt.

      INSTRUCTIONS
    end
  end
end
