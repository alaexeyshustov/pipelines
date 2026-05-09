module Evaluation
  class PromptImprover
    Error = Class.new(StandardError)

    EvaluationEntry = Data.define(:metric_name, :score, :justification)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert prompt engineer. You will be given a current agent system prompt,
      evaluation scores with justifications, and metric rubrics describing what each score measures.

      Your task: improve the system prompt to address weak areas (low scores) while preserving
      behaviors that already score well. Return ONLY a JSON object with:
      - "system_prompt": the improved system prompt (string)
      - "user_prompt": the improved user prompt (string)
    PROMPT

    def self.call(experiment:)
      new(experiment:).call
    end

    def initialize(experiment:)
      @experiment = experiment
    end

    def call
      current_prompt = @experiment.prompt
      raise ArgumentError, "Experiment has no associated prompt" if current_prompt.nil?

      metrics         = Evaluation::Metric.where(agent_name: current_prompt.name, active: true)
      evaluation_data = load_evaluation_data

      user_message = build_improvement_message(
        current_prompt:,
        evaluation_data:,
        metrics:
      )

      improved = call_llm(user_message)

      Orchestration::Prompt.create!(
        name: current_prompt.name,
        system_prompt: improved[:system_prompt],
        user_prompt: improved[:user_prompt].presence || current_prompt.user_prompt
      )
    end

    private

    def model
      ENV.fetch("EVALUATION_LLM_MODEL", "claude-sonnet-4-6")
    end

    def load_evaluation_data
      Evaluation::Justification
        .eager_load(:evaluation_result)
        .where(leva_evaluation_results: { experiment_id: @experiment.id })
        .map { |j| EvaluationEntry.new(metric_name: j.metric_name, score: j.evaluation_result.score, justification: j.justification) }
    end

    def build_improvement_message(current_prompt:, evaluation_data:, metrics:)
      rubrics = metrics.map { |m| "- #{m.name}: #{m.description}" }.join("\n")

      score_lines = evaluation_data.map do |r|
        "- #{r.metric_name}: #{r.score}/5 — #{r.justification}"
      end.join("\n")

      <<~MSG
        ## Current System Prompt
        <current_system_prompt>
        #{current_prompt.system_prompt}
        </current_system_prompt>

        ## Current User Prompt
        <current_user_prompt>
        #{current_prompt.user_prompt}
        </current_user_prompt>

        ## Evaluation Results
        <evaluation_results>
        #{score_lines.presence || "(no evaluation results)"}
        </evaluation_results>

        ## Metric Rubrics
        #{rubrics.presence || "(no metrics defined)"}
      MSG
    end

    def call_llm(user_message)
      response = RubyLLM.chat(model:)
                        .with_instructions(SYSTEM_PROMPT)
                        .ask(user_message)

      parse_response(response.content)
    rescue Error
      raise
    rescue StandardError => e
      Rails.logger.error("[PromptImprover] LLM call failed: #{e.message}")
      raise Error, "LLM call failed"
    end

    def parse_response(content)
      parsed = JSON.parse(content)
      raise Error, "Expected JSON object" unless parsed.is_a?(Hash)
      raise Error, "Missing system_prompt in LLM response" if parsed["system_prompt"].blank?

      { system_prompt: parsed["system_prompt"], user_prompt: parsed["user_prompt"].to_s }
    rescue JSON::ParserError => e
      raise Error, "Prompt improvement returned invalid JSON: #{e.message}"
    end
  end
end
