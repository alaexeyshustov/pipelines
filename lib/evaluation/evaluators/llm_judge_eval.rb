module Evaluation
  module Evaluators
    class LLMJudgeEval
      @judge_model = LlmModels.judge

      class << self
        attr_accessor :judge_model
      end

      def evaluate(sample, dataset_sample, agent_name:, model: self.class.judge_model)
        metrics = Metric.for_agent(agent_name).active
        return [] if metrics.none?

        if sample.tool_calls.blank? && sample.output.blank?
          Rails.logger.error("LLMJudgeEval: both tool_calls and output are blank")
          return []
        end

        user_input = build_user_message(sample:, dataset_sample:, metrics:)
        call_judge(user_input:, model:)
      rescue JSON::ParserError, TypeError => e
        Rails.logger.error("LLMJudgeEval: failed to parse sample data: #{e.message}")
        []
      end

      def evaluate_and_store(experiment, sample)
        dataset_sample = sample.dataset_sample
        return [] unless dataset_sample

        agent_name = experiment.agent_name
        return [] unless agent_name

        judge_model = experiment.evaluation_model.presence || self.class.judge_model
        metric_results = evaluate(sample, dataset_sample, agent_name: agent_name, model: judge_model)
        return [] if metric_results.empty?

        eval_results = metric_results.map do |result|
          {
            experiment_id: experiment.id,
            dataset_sample_id: dataset_sample.id,
            sample_id: sample.id,
            score: result[:score].to_f,
            evaluator_class: self.class.name
          }
        end

        inserted_ids = [] #: Array[Integer]
        ActiveRecord::Base.transaction do
          inserted = EvaluationResult.insert_all!(eval_results)
          inserted_ids = inserted.map { |id| id["id"].to_i }
          justifications = inserted_ids.zip(metric_results).filter_map do |id, result|
            next unless result

            {
              evaluation_result_id: id,
              metric_name: result[:metric_name],
              justification: result[:justification]
            }
          end
          Justification.insert_all!(justifications)
        end

        results_by_id = EvaluationResult.where(id: inserted_ids).index_by(&:id)
        inserted_ids.filter_map { |id| results_by_id[id] }
      end

      private

      def fetch_instructions(sample)
        sample.prompt&.system_prompt
      end

      def call_judge(user_input:, model: self.class.judge_model)
        response = Evaluation::Judge::Agent.create.with_model(model).ask(user_input)
        parse_judge_response(response.content)
      rescue StandardError => e
        Rails.logger.error("LLMJudgeEval: judge call failed: #{e.message}")
        []
      end

      def build_user_message(sample:, dataset_sample:, metrics:)
        message = {
          instructions: fetch_instructions(sample),
          input: dataset_sample.input,
          actual_tool_calls: sample.tool_calls || [],
          output: parse_output(sample.output),
          metrics: metrics.map { |m| { name: m.name, description: m.description } }
        }
        expected = dataset_sample.expected_tool_calls
        message[:expected_tool_calls] = expected unless expected.nil?
        message.to_json
      end

      def parse_output(output)
        return "" if output.blank?

        JSON.parse(output)
      rescue JSON::ParserError, TypeError
        output
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
