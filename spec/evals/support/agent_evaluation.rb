# Shared base for the regression gate (native RubyLLM::Evaluation, see docs/evals.md#regression-gate).
#
# Each subclass pins one code-defined agent (Orchestration::Agents::*) to a handful of golden cases.
# Decisions:
# - Cases are Evaluation::DatasetCases of in-memory DatasetSample rows (no DB state is needed to
#   load them), so the gate and the experiments share one case shape.
# - The agent runs tool-free (with_tools(nil)): golden cases must be answerable from the input, and the
#   gate can never mutate data or touch Gmail (same guarantee as the sampler's write-tool blocking).
# - Grading uses a native RubyLLM::Judge on the judgment model (LlmModels.judge) with declared
#   criteria, each with a `minimum:` so a case passes only when every criterion clears its threshold.
module Evaluation
  module Regression
    class GoldenJudge < RubyLLM::Judge
      model { LlmModels.judge }
    end

    class AgentEvaluation < RubyLLM::Evaluation
      evaluator GoldenJudge

      class << self
        attr_reader :agent_class

        def agent(klass)
          @agent_class = klass
        end

        # golden: Array of { input:, expected_tool_calls: (optional) }; ids are positional (1-based).
        def golden(entries)
          dataset do
            entries.each_with_index.map do |entry, index|
              sample = Evaluation::DatasetSample.new(
                id: index + 1, input: entry.fetch(:input), expected_tool_calls: entry[:expected_tool_calls]
              )
              Evaluation::DatasetCases.for_sample(sample)
            end
          end
        end

        def build_agent
          klass = agent_class or raise ArgumentError, "#{name}: declare agent"
          klass.new.with_tools(nil)
        end
      end

      def perform(input)
        agent = self.class.build_agent
        agent.ask(JSON.generate(input))
        agent
      end
    end
  end
end
