module Evaluation
  class PromptImprover
    class Error < StandardError; end

    def self.call(experiment:, model: LlmModels.evaluation)
      new(experiment:, model:).call
    end

    def initialize(experiment:, model:)
      @experiment = experiment
      @model = model
    end

    def call
      current_prompt = @experiment.prompt
      raise ArgumentError, "Experiment has no associated prompt" if current_prompt.nil?

      input = build_improvement_message(current_prompt:, evaluation_data:, metrics: metrics(current_prompt))

      improved = UsageScope.call(@experiment) { run_agent(input) }

      Evaluation::PromptCreator.call(
        name: current_prompt.name,
        system_prompt: improved[:system_prompt],
        user_prompt: improved[:user_prompt].presence || current_prompt.user_prompt,
        output_schema: current_prompt.output_schema
      )
    end

    private

    def evaluation_data
      Justification
        .eager_load(:evaluation_result)
        .where(evaluation_evaluation_results: { experiment_id: @experiment.id })
        .to_a
    end

    def metrics(current_prompt)
      Metric.active_for_agent(current_prompt.name.to_s).to_a
    end

    def build_improvement_message(current_prompt:, evaluation_data:, metrics:)
      message = build_message_data(current_prompt, evaluation_data, metrics).to_json
      append_output_schema(message, current_prompt.name.to_s)
    end

    def build_message_data(current_prompt, evaluation_data, metrics)
      {
        experiment_id: @experiment.id,
        prompt_name: current_prompt.name.to_s,
        system_prompt: current_prompt.system_prompt,
        metrics: metrics.map { |m| { name: m.name, description: m.description, kind: m.kind, levels: m.levels, minimum: m.minimum } },
        scores: evaluation_data.map { |j| score_entry(j) }
      }
    end

    # Score is the normalized 0.0..1.0 grade; the justification is the Grader's derived text (level description +
    # percentages), the only "reason" the native judge provides.
    def score_entry(justification)
      result = justification.evaluation_result
      {
        metric_name: justification.metric_name,
        score: result.score,
        passed: result.passed,
        confidence: result.confidence,
        justification: justification.justification
      }
    end

    def append_output_schema(message, agent_name)
      agent_schema = Orchestration::AgentCatalog.find(agent_name)&.output_schema
      return message if agent_schema.blank?

      message + "\n\n<output_schema>\n#{agent_schema.to_json}\n</output_schema>"
    end

    def run_agent(input)
      response = build_agent.ask(input)
      log_actual_model(response)
      parse_response(response)
    rescue Error
      raise
    rescue StandardError => e
      Rails.logger.error("[PromptImprover] LLM call failed: #{e.message}")
      raise Error, "LLM call failed"
    end

    def build_agent
      agent = Evaluation::Improvement::Agent.create
      agent.with_model(@model)
      agent.after_fallback { |fallback| log_fallback(fallback) }
      agent
    end

    def log_fallback(fallback)
      Rails.logger.warn("[PromptImprover] fallback #{fallback.from&.id} -> #{fallback.id}: #{fallback.error.class}")
    end

    def log_actual_model(response)
      actual = response.model
      Rails.logger.info("[PromptImprover] experiment #{@experiment.id} answered by #{actual}") if actual.to_s != @model.to_s
    end

    def parse_response(response)
      parsed = StructuredOutput.from(response)
      system_prompt = parsed["system_prompt"]
      raise Error, "Missing system_prompt in LLM response" unless system_prompt.is_a?(String) && system_prompt.present?

      { system_prompt: system_prompt, user_prompt: parsed["user_prompt"].to_s }
    rescue JSON::ParserError, ArgumentError => e
      raise Error, "Prompt improvement returned invalid output: #{e.message}"
    end
  end
end
