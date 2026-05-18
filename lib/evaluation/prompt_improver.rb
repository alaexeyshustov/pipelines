module Evaluation
  class PromptImprover
    Error = Class.new(StandardError)

    def self.call(experiment:, model: ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4"))
      new(experiment:, model:).call
    end

    def initialize(experiment:, model:)
      @experiment = experiment
      @model = model
    end

    def call
      current_prompt = @experiment.prompt
      raise ArgumentError, "Experiment has no associated prompt" if current_prompt.nil?

      input = build_improvement_message(current_prompt:, evaluation_data:, metrics:)

      improved = run_agent(input)

      Evaluation::Prompt.create!(
        name: current_prompt.name,
        system_prompt: improved[:system_prompt],
        user_prompt: improved[:user_prompt].presence || current_prompt.user_prompt,
        version: current_prompt.version,
        output_schema: improved[:output_schema]
      )
    end

    private

    def evaluation_data
      Evaluation::Justification
        .eager_load(:evaluation_result)
        .where(evaluation_evaluation_results: { experiment_id: @experiment.id })
    end

    def metrics
      Metric.where(agent_name: @experiment.prompt.name, active: true)
    end


    def build_improvement_message(current_prompt:, evaluation_data:, metrics:)
      data = {
        experiment_id: @experiment.id,
        prompt_name: current_prompt.name,
        system_prompt: current_prompt.system_prompt,
        metrics: metrics.map { |m| { name: m.name, description: m.description } },
        scores: evaluation_data.map { |r| { metric_name: r.metric_name, score: r.evaluation_result.score, justification: r.justification } }
      }

      message = data.to_json

      agent_schema = Orchestration::Agent.find_by(name: current_prompt.name)&.output_schema
      message += "\n\n<output_schema>\n#{agent_schema.to_json}\n</output_schema>" if agent_schema.present?

      message
    end

    def run_agent(input)
      response = Evaluation::Improvement::Agent.create.with_model(@model).ask(input)
      parse_response(response.content)
    rescue Error
      raise
    rescue StandardError => e
      Rails.logger.error("[PromptImprover] LLM call failed: #{e.message}")
      raise Error, "LLM call failed"
    end

    def parse_response(content)
      parsed = content.is_a?(Hash) ? content : JSON.parse(content)
      raise Error, "Expected JSON object" unless parsed.is_a?(Hash)
      raise Error, "Missing system_prompt in LLM response" if parsed["system_prompt"].blank?

      { system_prompt: parsed["system_prompt"], user_prompt: parsed["user_prompt"].to_s }
    rescue JSON::ParserError => e
      raise Error, "Prompt improvement returned invalid JSON: #{e.message}"
    end
  end
end
