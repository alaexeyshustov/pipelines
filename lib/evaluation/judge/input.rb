module Evaluation
  module Judge
    # The material the judge sees: agent instructions, input, expected/actual tool calls, output, output schema.
    # RubyLLM::Judge only accepts JSON-compatible data, so the payload is round-tripped through JSON.
    # The tool-calling dimension is omitted when the dataset sample has no expected_tool_calls.
    class Input
      def self.call(sample:, dataset_sample:)
        prompt = sample.prompt
        payload = {
          instructions: prompt&.system_prompt,
          input: dataset_sample.input,
          actual_tool_calls: sample.tool_calls || [],
          output: JSON::Helpers.safe_parse(sample.output, fallback: sample.output.to_s),
          expected_tool_calls: dataset_sample.expected_tool_calls,
          output_schema: prompt&.output_schema.presence
        }
        JSON.parse(payload.compact.to_json) # : json_object
      end
    end
  end
end
