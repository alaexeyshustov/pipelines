module Evaluation
  module Improvement
    class Agent < ::RubyLLM::Agent
      chat_model Chat
      model LlmModels.evaluation
      tools LoadSamplesTool, ListExperimentsTool, GetExperimentJustificationsTool, GetExperimentPromptTool

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

      Before writing the improved prompt, use the available tools to understand the direction of
      past improvement attempts for this agent:
      - Call `list_experiments` with the prompt_name and current experiment_id to see the score
        trajectory across all previous experiments (per-metric averages and overall average).
      - Call `get_experiment_justifications` on any past experiment to read the judge's full
        reasoning for that run — useful for understanding what went wrong or right.
      - Call `get_experiment_prompt` on any past experiment to see the exact prompt text that
        produced those scores — useful for understanding what changes have already been tried.

      Use this history to avoid repeating directions that have already been tried without success,
      and to build on directions that showed improvement.

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
