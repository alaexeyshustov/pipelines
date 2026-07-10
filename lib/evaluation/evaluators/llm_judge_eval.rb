module Evaluation
  module Evaluators
    # rubocop:disable Metrics/ClassLength
    class LLMJudgeEval
      @judge_model = LlmModels.judge

      class << self
        attr_accessor :judge_model
      end

      def evaluate(sample, dataset_sample, agent_name:, model: self.class.judge_model)
        metrics = Metric.active_for_agent(agent_name).to_a # : Array[Evaluation::Metric]
        return [] if metrics.empty?
        return log_blank_sample_error if sample.tool_calls.blank? && sample.output.blank?

        call_judge(user_input: build_user_message(sample:, dataset_sample:, metrics:), model:)
      rescue JSON::ParserError, TypeError => e
        Rails.logger.error("LLMJudgeEval: failed to parse sample data: #{e.message}")
        []
      end

      def evaluate_and_store(experiment, sample)
        dataset_sample = sample.dataset_sample
        return [] unless dataset_sample

        agent_name = experiment.agent_name
        return [] unless agent_name

        judge_model    = experiment.evaluation_model.presence || self.class.judge_model
        metric_results = evaluate(sample, dataset_sample, agent_name: agent_name, model: judge_model) # : Array[metric_result]
        return [] if metric_results.empty?

        inserted_ids = insert_results_transactionally(metric_results, experiment, dataset_sample, sample)
        load_stored_results(inserted_ids)
      end

      private

      def log_blank_sample_error
        Rails.logger.error("LLMJudgeEval: both tool_calls and output are blank")
        []
      end

      def load_stored_results(inserted_ids)
        results      = EvaluationResult.where(id: inserted_ids).to_a # : Array[EvaluationResult]
        results_by_id = results.index_by(&:id) # : Hash[Integer, EvaluationResult]
        inserted_ids.filter_map { |id| results_by_id[id] }
      end

      def coerce_to_array(content)
        if content.is_a?(Hash)
          Array(content["evaluations"])
        elsif content.is_a?(Array)
          content
        else
          str_content = content #: String
          JSON.parse(str_content)
        end
      end

      def insert_results_transactionally(metric_results, experiment, dataset_sample, sample)
        eval_results = build_eval_results(metric_results, experiment, dataset_sample, sample)
        inserted_ids = [] #: Array[Integer]
        ActiveRecord::Base.transaction do
          inserted = EvaluationResult.insert_all!(eval_results) # : ActiveRecord::Result
          inserted_ids = inserted.map { |row| Integer(row["id"]) } # : Array[Integer]
          Justification.insert_all!(build_justifications(inserted_ids, metric_results))
        end
        inserted_ids
      end

      def build_eval_results(metric_results, experiment, dataset_sample, sample)
        metric_results.map do |result|
          {
            experiment_id: experiment.id,
            dataset_sample_id: dataset_sample.id,
            sample_id: sample.id,
            score: Float(result[:score]),
            evaluator_class: self.class.name
          }
        end
      end

      def build_justifications(inserted_ids, metric_results)
        inserted_ids.zip(metric_results).filter_map do |id, result|
          next unless result

          {
            evaluation_result_id: id,
            metric_name: result[:metric_name],
            justification: result[:justification]
          }
        end
      end

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
        entries = coerce_to_array(content)
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

        score, metric_name, justification = extract_score_fields(entry, raw_score)
        return log_invalid_entry(index) unless valid_score_entry?(score, metric_name, justification)

        { metric_name: metric_name, score: score, justification: justification }
      rescue ArgumentError, TypeError
        Rails.logger.warn("LLMJudgeEval: dropping entry #{index}: unparseable score #{raw_score.inspect}")
        nil
      end

      def extract_score_fields(entry, raw_score)
        [ Float(raw_score), entry["metric_name"].to_s.strip, entry["justification"].to_s.strip ] #: [Float, String, String]
      end

      def valid_score_entry?(score, metric_name, justification)
        score.between?(1.0, 5.0) && metric_name.present? && justification.present?
      end

      def log_invalid_entry(index)
        Rails.logger.warn("LLMJudgeEval: dropping entry #{index}: score out of range or missing fields")
        nil
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
