module Evaluation
  module Evaluators
    class LLMJudgeEval < BaseEval
      @judge_model = LlmModels.judge

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

        user_input = build_user_message(runner_result:, recordable:, metrics:)
        call_judge(user_input:, model:)
      rescue JSON::ParserError, TypeError => e
        Rails.logger.error("LLMJudgeEval: failed to parse prediction JSON: #{e.message}")
        []
      end

      def evaluate_and_store(experiment, runner_result)
        recordable = runner_result.dataset_record.recordable
        judge_model = experiment.evaluation_model.presence || self.class.judge_model
        metric_results = evaluate(runner_result, recordable, model: judge_model)

        eval_results = metric_results.map do |result|
           {
            experiment_id: experiment.id,
            dataset_record_id: runner_result.dataset_record.id,
            runner_result_id: runner_result.id,
            score: result[:score].to_f,
            evaluator_class: self.class.name
          }
        end

        ids = [] #: Array[Integer]
        ActiveRecord::Base.transaction do
          inserted = EvaluationResult.insert_all!(eval_results)
          ids = inserted.map { |id| id["id"].to_i }
          justifications = metric_results.map do |result|
            {
              evaluation_result_id: ids.shift,
              metric_name: result[:metric_name],
              justification: result[:justification]
            }
          end
          Justification.insert_all!(justifications)
        end

        EvaluationResult.where(id: ids).to_a
      end

      private

      def agent_name(recordable)
        action = recordable.step_action.action
        action.agent? ? action.agent&.name : action.agent_class
      end

      def fetch_instructions(runner_result)
        runner_result.prompt&.system_prompt
      end

      def call_judge(user_input:, model: self.class.judge_model)
        response = Evaluation::Judge::Agent.create.with_model(model).ask(user_input)
        parse_judge_response(response.content)
      rescue StandardError => e
        Rails.logger.error("LLMJudgeEval: judge call failed: #{e.message}")
        []
      end

      def build_user_message(runner_result:, recordable:, metrics:)
        prediction = JSON.parse(runner_result.prediction)
        default_tool_calls = [] #: Array[untyped]

        {
          instructions: fetch_instructions(runner_result),
          input: recordable.input,
          expected_tool_calls: ToolCallExtractor.call(recordable.chat),
          actual_tool_calls: prediction.fetch("tool_calls", default_tool_calls),
          output: prediction.fetch("output", ""),
          metrics: metrics.map { |m| { name: m.name, description: m.description } }
        }.to_json
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
