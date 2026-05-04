class LLMJudgeEval < Leva::BaseEval
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an impartial LLM judge evaluating an AI agent's response.
    You will be given the agent's instructions, the input it received, the expected tool call sequence,
    the actual tool call sequence, the output, and a set of evaluation metrics with rubrics.

    For each metric, assign a score from 1 to 5 and provide a justification.
    Return ONLY a JSON array with no additional text. Each element must have:
    - "metric_name": the metric name (string)
    - "score": integer from 1 to 5
    - "justification": explanation of the score (string)
  PROMPT

  @judge_model = ENV.fetch("JUDGE_LLM_MODEL", "claude-sonnet-4-6")

  class << self
    attr_accessor :judge_model
  end

  def evaluate(runner_result, recordable)
    metrics = Evaluation::Metric.for_agent(agent_name(recordable)).active
    return [] if metrics.none?

    if runner_result.prediction.blank?
      Rails.logger.error("LLMJudgeEval: prediction is blank")
      return []
    end

    prompt_text = fetch_instructions(agent_name(recordable))
    prediction = JSON.parse(runner_result.prediction)
    expected_tool_calls = Evaluation::ToolCallExtractor.call(recordable.chat)

    call_judge(
      instructions: prompt_text,
      input: recordable.input,
      expected_tool_calls: expected_tool_calls,
      actual_tool_calls: prediction.fetch("tool_calls", []),
      output: prediction.fetch("output", ""),
      metrics: metrics
    )
  rescue JSON::ParserError, TypeError => e
    Rails.logger.error("LLMJudgeEval: failed to parse prediction JSON: #{e.message}")
    []
  end

  def evaluate_and_store(experiment, runner_result)
    recordable = runner_result.dataset_record.recordable
    results = evaluate(runner_result, recordable)

    results.map do |metric_result|
      ActiveRecord::Base.transaction do
        eval_result = Leva::EvaluationResult.create!(
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

  def fetch_instructions(agent_name)
    Orchestration::Prompt
      .where(name: agent_name)
      .order(version: :desc, id: :desc)
      .first
      &.system_prompt
  end

  def call_judge(instructions:, input:, expected_tool_calls:, actual_tool_calls:, output:, metrics:)
    user_message = build_user_message(
      instructions: instructions,
      input: input,
      expected_tool_calls: expected_tool_calls,
      actual_tool_calls: actual_tool_calls,
      output: output,
      metrics: metrics
    )

    response = RubyLLM.chat(model: self.class.judge_model)
                      .with_temperature(0)
                      .with_instructions(SYSTEM_PROMPT)
                      .ask(user_message)

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
      #{output}

      ## Evaluation Metrics
      #{rubrics}
    MSG
  end

  def parse_judge_response(content)
    parsed = JSON.parse(content)
    raise ArgumentError, "expected Array" unless parsed.is_a?(Array)

    parsed.each_with_index.filter_map { |entry, i| normalize_entry(entry, i) }
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
