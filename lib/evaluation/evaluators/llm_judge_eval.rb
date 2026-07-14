module Evaluation
  module Evaluators
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

        JudgeResultWriter.call(
          metric_results: metric_results,
          experiment: experiment,
          dataset_sample: dataset_sample,
          sample: sample,
          evaluator_class: self.class.name
        )
      end

      private

      def log_blank_sample_error
        Rails.logger.error("LLMJudgeEval: both tool_calls and output are blank")
        []
      end

      def fetch_instructions(sample)
        sample.prompt&.system_prompt
      end

      def fetch_output_schema(sample)
        sample.prompt&.output_schema
      end

      def call_judge(user_input:, model: self.class.judge_model)
        response = Evaluation::Judge::Agent.create.with_model(model).ask(user_input)
        JudgeResponseParser.parse(response.content)
      rescue StandardError => e
        Rails.logger.error("LLMJudgeEval: judge call failed: #{e.message}")
        []
      end

      def build_user_message(sample:, dataset_sample:, metrics:)
        message = {
          instructions: fetch_instructions(sample),
          input: dataset_sample.input,
          actual_tool_calls: sample.tool_calls || [],
          output: JudgeResponseParser.parse_output(sample.output),
          metrics: metrics.map { |m| { name: m.name, description: m.description } }
        }
        expected = dataset_sample.expected_tool_calls
        message[:expected_tool_calls] = expected unless expected.nil?
        schema = fetch_output_schema(sample)
        message[:output_schema] = schema if schema.present?
        message.to_json
      end
    end
  end
end
