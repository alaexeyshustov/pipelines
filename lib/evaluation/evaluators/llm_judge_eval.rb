module Evaluation
  module Evaluators
    class LLMJudgeEval
      @judge_model = LlmModels.judge

      class << self
        attr_accessor :judge_model
      end

      def evaluate(sample, dataset_sample, agent_name:, model: self.class.judge_model)
        metrics = Metric.for_agent(agent_name).where(active: true).to_a # : Array[Evaluation::Metric]
        return [] if metrics.empty?

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
        metric_results = evaluate(sample, dataset_sample, agent_name: agent_name, model: judge_model) # : Array[Hash[Symbol, untyped]]
        return [] if metric_results.empty?

        eval_results = metric_results.map do |result|
          {
            experiment_id: experiment.id,
            dataset_sample_id: dataset_sample.id,
            sample_id: sample.id,
            score: Float(result[:score]),
            evaluator_class: self.class.name
          }
        end

        inserted_ids = [] #: Array[Integer]
        ActiveRecord::Base.transaction do
          inserted = EvaluationResult.insert_all!(eval_results) # : ActiveRecord::Result
          inserted_ids = inserted.map { |row| Integer(row["id"]) } # : Array[Integer]
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

        results = EvaluationResult.where(id: inserted_ids).to_a # : Array[EvaluationResult]
        results_by_id = results.index_by(&:id) # : Hash[Integer, EvaluationResult]
        inserted_ids.filter_map { |id| results_by_id[id] }
      end

      private

      def fetch_instructions(sample)
        sample.prompt&.system_prompt
      end

      def fetch_output_schema(sample)
        sample.prompt&.output_schema
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
        schema = fetch_output_schema(sample)
        message[:output_schema] = schema if schema.present?
        message.to_json
      end

      def parse_output(output)
        return "" if output.blank?

        JSON.parse(output)
      rescue JSON::ParserError, TypeError
        output
      end

      def parse_judge_response(content)
        entries =
          if content.is_a?(Hash)
            Array(content["evaluations"])
          elsif content.is_a?(Array)
            content
          else
            str_content = content #: String
            JSON.parse(str_content)
          end
        raise ArgumentError, "expected Array" unless entries.is_a?(Array)

        entries.each_with_index.filter_map { |entry, i| normalize_entry(entry, i) }
      rescue JSON::ParserError, ArgumentError => e
        Rails.logger.error("LLMJudgeEval: failed to parse judge response: #{e.message}")
        []
      end

      def normalize_entry(entry, index)
        return nil unless entry.is_a?(Hash)

        raw_score = entry["score"]
        return nil if raw_score.nil?

        score = Float(raw_score).to_f
        metric_name = entry["metric_name"].to_s.strip
        justification = entry["justification"].to_s.strip

        unless score.between?(1.0, 5.0) && metric_name.present? && justification.present?
          Rails.logger.warn("LLMJudgeEval: dropping entry #{index}: score out of range or missing fields")
          return nil
        end

        { metric_name: metric_name, score: score, justification: justification }
      rescue ArgumentError, TypeError
        Rails.logger.warn("LLMJudgeEval: dropping entry #{index}: unparseable score #{raw_score.inspect}")
        nil
      end
    end
  end
end
