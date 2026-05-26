module Evaluation
  module Judge
    class Agent < ::RubyLLM::Agent
      chat_model Chat
      model LlmModels.judge

      # steep:ignore:start
      schema do
        array :evaluations do
          object do
            string  :metric_name,   description: "The metric name being scored"
            integer :score,         description: "Score from 1 to 5 (inclusive)"
            string  :justification, description: "Explanation of the score"
          end
        end
      end
      # steep:ignore:end

      instructions <<~INSTRUCTIONS
        You are an impartial LLM judge evaluating an AI agent's response.

        ## Input Schema
        You will receive a JSON object with the following structure:
        {
          "instructions": "the agent's system prompt text",
          "input": { ... },
          "expected_tool_calls": [ ... ],
          "actual_tool_calls": [ ... ],
          "output": "the agent's final output",
          "output_schema": { ... },
          "metrics": [{ "name": "metric_name", "description": "rubric description" }, ...]
        }

        "output_schema" is the JSON Schema the agent was instructed to conform to.
        When present, use it to judge whether the output matches the expected structure.

        ## Task
        For each metric in "metrics", assign an integer score from 1 to 5 and write a concise justification.
        Return all scores via the structured output schema.
      INSTRUCTIONS
    end
  end
end
