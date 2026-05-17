module Evaluation
  class PromptImprover
    Error = Class.new(StandardError)

    EvaluationEntry = Data.define(:metric_name, :score, :justification)

    IMPROVEMENT_PROMPT = <<~PROMPT.freeze
      You are an expert prompt engineer. You will be given a current agent system prompt,
      evaluation scores with justifications, metric rubrics, and sample inputs with actual
      agent outputs.

      Your task: improve the system prompt to address weak areas (low scores) while preserving
      behaviors that already score well.

      IMPORTANT constraints:
      - Do NOT add output format descriptions, JSON schema examples, or structured output
        instructions to the improved prompt. The output schema is enforced at the API level
        via response_format and must not appear in the prompt text — duplicating it adds noise
        and degrades model performance.
      - The output schema section (if present) is provided for your reference only, so you
        understand what the agent produces. Do not replicate it in the improved prompt.
    PROMPT

    class ImprovementSchema < RubyLLM::Schema
      string :system_prompt, required: true, description: "The improved system prompt text. Must be non-empty."
      string :user_prompt, required: true, description: "The improved user prompt text. Can be empty if no changes are needed."
    end

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
      samples         = load_samples
      output_schema   = Orchestration::Agent.find_by(name: current_prompt.name)&.output_schema

      user_message = build_improvement_message(
        current_prompt:,
        evaluation_data:,
        metrics:,
        samples:,
        output_schema:
      )

      improved = call_llm(user_message)

      Evaluation::Prompt.create!(
        name: current_prompt.name,
        system_prompt: improved[:system_prompt],
        user_prompt: improved[:user_prompt].presence || current_prompt.user_prompt,
        version: current_prompt.version,
        output_schema: output_schema
      )
    end

    private

    def model
      ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")
    end

    def load_evaluation_data
      Evaluation::Justification
        .eager_load(:evaluation_result)
        .where(evaluation_evaluation_results: { experiment_id: @experiment.id })
        .map { |j| EvaluationEntry.new(metric_name: j.metric_name, score: j.evaluation_result.score, justification: j.justification) }
    end

    def load_samples
      Evaluation::RunnerResult
        .where(experiment: @experiment)
        .includes(dataset_record: :recordable)
        .order(Arel.sql("RANDOM()"))
        .limit(5)
        .filter_map do |rr|
          prediction = JSON.parse(rr.prediction)
          recordable = rr.dataset_record&.recordable
          next unless recordable
          { input: recordable.input, output: prediction.fetch("output", "") }
        rescue JSON::ParserError
          next
        end
    end

    def build_improvement_message(current_prompt:, evaluation_data:, metrics:, samples:, output_schema:)
      rubrics = metrics.map { |m| "- #{m.name}: #{m.description}" }.join("\n")

      score_lines = evaluation_data.map do |r|
        "- #{r.metric_name}: #{r.score}/5 — #{r.justification}"
      end.join("\n")

      sample_lines = samples.map.with_index(1) do |s, i|
        "### Sample #{i}\nInput: #{JSON.generate(s[:input])}\nOutput: #{s[:output]}"
      end.join("\n\n")

      schema_section = if output_schema.present?
        <<~SECTION
          ## Output Schema (API-enforced — for reference only, DO NOT include in improved prompt)
          <output_schema>
          #{JSON.pretty_generate(output_schema)}
          </output_schema>
        SECTION
      end

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

        ## Sample Inputs and Actual Agent Outputs
        <samples>
        #{sample_lines.presence || "(no samples available)"}
        </samples>

        #{schema_section&.chomp}
      MSG
    end

    def call_llm(user_message)
      response = RubyLLM.chat(model:)
                        .with_instructions(IMPROVEMENT_PROMPT)
                        .with_schema(ImprovementSchema)
                        .ask(user_message)

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
