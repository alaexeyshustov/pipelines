module Evaluation
  module Evaluators
    class LLMJudgeEval < BaseEval
      @judge_model = ENV.fetch("JUDGE_LLM_MODEL", "gpt-5.4")

      class << self
        attr_accessor :judge_model
      end

      def evaluate(runner_result, recordable, model: self.class.judge_model)
        unless recordable.respond_to?(:input) && recordable.respond_to?(:step_action)
          raise ArgumentError, "LLMJudgeEval requires a recordable with #input and #step_action, got #{recordable.class}"
        end

        metrics = Metric.for_agent(agent_name(recordable)).active
        return [] if metrics.none?

        if runner_result.prediction.blank?
          Rails.logger.error("LLMJudgeEval: prediction is blank")
          return []
        end

        prompt_text = fetch_instructions(runner_result)
        prediction = JSON.parse(runner_result.prediction)
        expected_tool_calls = ToolCallExtractor.call(recordable.chat)
        default_tool_calls = [] #: Array[untyped]
        actual_tool_calls = prediction.fetch("tool_calls", default_tool_calls)

        call_judge(
          instructions: prompt_text,
          input: recordable.input,
          expected_tool_calls: expected_tool_calls,
          actual_tool_calls: actual_tool_calls,
          output: prediction.fetch("output", ""),
          metrics: metrics,
          model: model
        )
      rescue JSON::ParserError, TypeError => e
        Rails.logger.error("LLMJudgeEval: failed to parse prediction JSON: #{e.message}")
        []
      end

      def evaluate_and_store(experiment, runner_result)
        recordable = runner_result.dataset_record.recordable
        judge_model = experiment.evaluation_model.presence || self.class.judge_model
        results = evaluate(runner_result, recordable, model: judge_model)

        results.map do |metric_result|
          ActiveRecord::Base.transaction do
            eval_result = Evaluation::EvaluationResult.create!(
              experiment: experiment,
              dataset_record: runner_result.dataset_record,
              runner_result: runner_result,
              score: metric_result[:score].to_f,
              evaluator_class: self.class.name
            )
            Evaluation::Justification.create!(
              evaluation_result: eval_result,
              metric_name: metric_result[:metric_name],
              justification: metric_result[:justification]
            )
            eval_result
          end
        end
      end

      private

      def agent_name(recordable)
        action = recordable.step_action.action
        action.agent? ? action.agent&.name : action.agent_class
      end

      def fetch_instructions(runner_result)
        runner_result.prompt&.system_prompt
      end

      def call_judge(instructions:, input:, expected_tool_calls:, actual_tool_calls:, output:, metrics:, model: self.class.judge_model)
        user_message = build_user_message(
          instructions: instructions,
          input: input,
          expected_tool_calls: expected_tool_calls,
          actual_tool_calls: actual_tool_calls,
          output: output,
          metrics: metrics
        )

        response = Evaluation::Judge::Agent.create.with_model(model).ask(user_message)
        parse_judge_response(response.content)
      rescue StandardError => e
        Rails.logger.error("LLMJudgeEval: judge call failed: #{e.message}")
        []
      end

      def build_user_message(instructions:, input:, expected_tool_calls:, actual_tool_calls:, output:, metrics:)
        rubrics = metrics.map { |m| "- #{m.name}: #{m.description}" }.join("\n")

        <<~MSG
          ## Agent Instructions
          #{instructions}

          ## Input
          #{JSON.pretty_generate(input)}

          ## Expected Tool Call Sequence
          #{JSON.pretty_generate(expected_tool_calls)}

          ## Actual Tool Call Sequence
          #{JSON.pretty_generate(actual_tool_calls)}

          ## Agent Output
          #{output.is_a?(String) ? output : JSON.pretty_generate(output)}

          ## Evaluation Metrics
          #{rubrics}
        MSG
      end

      def parse_judge_response(content)
        entries = content.is_a?(Hash) ? Array(content["evaluations"]) : JSON.parse(content)
        raise ArgumentError, "expected Array" unless entries.is_a?(Array)

        entries.each_with_index.filter_map { |entry, i| normalize_entry(entry, i) }
      rescue JSON::ParserError, ArgumentError => e
        Rails.logger.error("LLMJudgeEval: failed to parse judge response: #{e.message}")
        []
      end

      def normalize_entry(entry, index)
        score = Float(entry["score"])
        metric_name = entry["metric_name"].to_s.strip
        justification = entry["justification"].to_s.strip

        unless score.between?(1.0, 5.0) && metric_name.present? && justification.present?
          Rails.logger.warn("LLMJudgeEval: dropping entry #{index}: score out of range or missing fields")
          return nil
        end

        { metric_name: metric_name, score: score, justification: justification }
      rescue ArgumentError, TypeError
        Rails.logger.warn("LLMJudgeEval: dropping entry #{index}: unparseable score #{entry['score'].inspect}")
        nil
      end
    end
  end
end
