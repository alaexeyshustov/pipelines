require "rails_helper"

RSpec.describe LLMJudgeEval do
  subject(:eval_instance) { described_class.new }

  let(:agent_name) { "Emails::ClassifyAgent" }

  describe "#evaluate" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
    let(:action) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }
    let(:step_action) { create(:orchestration_step_action, action: action) }
    let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }
    let(:recordable) do
      create(:orchestration_action_run,
             step_action: step_action,
             pipeline_run: pipeline_run,
             status: "completed",
             input: { "email" => "subject: Job offer" })
    end
    let(:llm_response_body) do
      scores = JSON.generate([
        { "metric_name" => "tool_call_accuracy", "score" => 4, "justification" => "Correct tool called." },
        { "metric_name" => "output_quality", "score" => 5, "justification" => "Clear output." }
      ])
      { id: "chatcmpl-01", object: "chat.completion", model: "gpt-5.4", choices: [ { index: 0, message: { role: "assistant", content: scores }, finish_reason: "stop" } ], usage: { prompt_tokens: 200, completion_tokens: 80, total_tokens: 280 } }.to_json
    end
    let(:prompt_double) { instance_double(Orchestration::Prompt, system_prompt: "You are a classifier.") }
    let(:runner_result) do
      prediction = { tool_calls: [ { tool_name: "classify_email", arguments: { label: "offer" } } ], output: "Classified." }.to_json
      instance_double(
        Leva::RunnerResult,
        prediction: prediction,
        prompt: prompt_double,
        dataset_record: instance_double(Leva::DatasetRecord, recordable: recordable)
      )
    end

    before do
      create(:evaluation_metric, agent_name: agent_name, name: "tool_call_accuracy", description: "Score tool call order.")
      create(:evaluation_metric, agent_name: agent_name, name: "output_quality", description: "Score output quality.")

      allow(Evaluation::ToolCallExtractor).to receive(:call).and_return(
        [ { tool_name: "classify_email", arguments: { label: "offer" }, result: "done" } ]
      )

      stub_request(:post, %r{api\.openai\.com})
        .to_return(status: 200, body: llm_response_body, headers: { "Content-Type" => "application/json" })
    end

    context "when recordable does not implement the duck-type interface" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "raises ArgumentError with a descriptive message" do
        chat = create(:chat)
        runner_result = instance_double(Leva::RunnerResult, prediction: "{}")
        expect { eval_instance.evaluate(runner_result, chat) }.to raise_error(ArgumentError, /#input.*#step_action|#step_action.*#input/)
      end
    end



    it "returns per-metric scores with justifications" do
      results = eval_instance.evaluate(runner_result, recordable)
      expect(results.size).to eq(2)
      expect(results.first).to include(metric_name: "tool_call_accuracy", score: 4.0, justification: a_kind_of(String))
    end

    it "includes all metrics in the LLM request" do
      eval_instance.evaluate(runner_result, recordable)

      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        messages_text = body["messages"].to_s
        messages_text.include?("classify_email") &&
          messages_text.include?("tool_call_accuracy") &&
          messages_text.include?("output_quality")
      }
    end

    context "when output is a hash (structured JSON result)" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:runner_result) do
        prediction = {
          tool_calls: [],
          output: { results: [ { id: "abc123", tags: [ "job", "application" ] } ] }
        }.to_json
        instance_double(
          Leva::RunnerResult,
          prediction: prediction,
          prompt: prompt_double,
          dataset_record: instance_double(Leva::DatasetRecord, recordable: recordable)
        )
      end

      it "sends the output as valid JSON, not Ruby hash syntax" do
        eval_instance.evaluate(runner_result, recordable)

        expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
          body = JSON.parse(req.body)
          messages_text = body["messages"].map { |m| m["content"] }.join
          # Valid JSON uses colons; Ruby inspect would produce =>
          messages_text.include?('"id"') && !messages_text.include?("=>")
        }
      end
    end

    it "requests temperature 0 (gpt-5 models normalize this to 1.0 per provider requirements)" do
      eval_instance.evaluate(runner_result, recordable)

      # gpt-5* models require temperature=1.0 regardless of the requested value;
      # RubyLLM normalizes it automatically (see providers/openai/temperature.rb).
      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        JSON.parse(req.body)["temperature"] == 1.0
      }
    end

    context "when the LLM returns invalid JSON" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:llm_response_body) do
        { id: "chatcmpl-02", object: "chat.completion", model: "gpt-5.4", choices: [ { index: 0, message: { role: "assistant", content: "not json" }, finish_reason: "stop" } ], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }.to_json
      end

      it "returns an empty array without raising" do
        expect(eval_instance.evaluate(runner_result, recordable)).to eq([])
      end
    end

    context "when prediction is nil" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:runner_result) do
        instance_double(
          Leva::RunnerResult,
          prediction: nil,
          prompt: prompt_double,
          dataset_record: instance_double(Leva::DatasetRecord, recordable: recordable)
        )
      end

      it "returns an empty array without raising" do
        expect(eval_instance.evaluate(runner_result, recordable)).to eq([])
      end
    end

    context "when the LLM returns a score outside 1–5" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:llm_response_body) do
        scores = JSON.generate([
          { "metric_name" => "tool_call_accuracy", "score" => 10, "justification" => "Way off." }
        ])
        { id: "chatcmpl-03", object: "chat.completion", model: "gpt-5.4", choices: [ { index: 0, message: { role: "assistant", content: scores }, finish_reason: "stop" } ], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }.to_json
      end

      it "drops the invalid entry and returns an empty array" do
        expect(eval_instance.evaluate(runner_result, recordable)).to eq([])
      end
    end

    context "when no active metrics exist" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before { Evaluation::Metric.update_all(active: false) }

      it "skips the LLM call and returns an empty array" do
        result = eval_instance.evaluate(runner_result, recordable)
        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:post, %r{api\.openai\.com})
      end
    end
  end

  describe "#evaluate_and_store" do
    let!(:leva_dataset) { Leva::Dataset.create!(name: "test_dataset") }
    let!(:leva_prompt) { Orchestration::Prompt.create!(name: agent_name, system_prompt: "You are a classifier.", user_prompt: "Classify: {{input}}") }
    let!(:leva_experiment) { Leva::Experiment.create!(name: "test_exp", dataset: leva_dataset, status: :pending, prompt: leva_prompt, runner_class: "StubbedAgentRun", evaluator_classes: [ "LLMJudgeEval" ]) }
    let!(:leva_dataset_record) do
      classify_agent = create(:orchestration_agent, name: agent_name)
      action = create(:orchestration_action, kind: :agent, agent: classify_agent)
      step_action = create(:orchestration_step_action, action: action)
      action_run = create(:orchestration_action_run, step_action: step_action, status: "completed")
      Leva::DatasetRecord.create!(dataset: leva_dataset, recordable: action_run)
    end
    let!(:leva_runner_result) do
      Leva::RunnerResult.create!(
        experiment: leva_experiment,
        dataset_record: leva_dataset_record,
        prompt: leva_prompt,
        prediction: { tool_calls: [], output: "classified" }.to_json,
        runner_class: "StubbedAgentRun"
      )
    end

    before do
      create(:evaluation_metric, agent_name: agent_name, name: "tool_call_accuracy", description: "Tool call accuracy.")
      create(:evaluation_metric, agent_name: agent_name, name: "output_quality", description: "Output quality.")
      allow(Evaluation::ToolCallExtractor).to receive(:call).and_return([])

      scores = JSON.generate([
        { "metric_name" => "tool_call_accuracy", "score" => 4, "justification" => "Good." },
        { "metric_name" => "output_quality", "score" => 5, "justification" => "Excellent." }
      ])
      body = { id: "chatcmpl-01", object: "chat.completion", model: "gpt-5.4", choices: [ { index: 0, message: { role: "assistant", content: scores }, finish_reason: "stop" } ], usage: { prompt_tokens: 200, completion_tokens: 80, total_tokens: 280 } }.to_json
      stub_request(:post, %r{api\.openai\.com})
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
    end

    it "creates one EvaluationResult per metric" do
      expect {
        eval_instance.evaluate_and_store(leva_experiment, leva_runner_result)
      }.to change(Leva::EvaluationResult, :count).by(2)
    end

    it "creates one Justification per metric" do
      expect {
        eval_instance.evaluate_and_store(leva_experiment, leva_runner_result)
      }.to change(Evaluation::Justification, :count).by(2)
    end

    it "stores scores between 1 and 5" do
      eval_instance.evaluate_and_store(leva_experiment, leva_runner_result)
      expect(Leva::EvaluationResult.last(2).map(&:score)).to all(be_between(1, 5))
    end

    it "links justifications to their evaluation results" do
      eval_instance.evaluate_and_store(leva_experiment, leva_runner_result)
      expect(Evaluation::Justification.last.evaluation_result).to be_a(Leva::EvaluationResult)
    end
  end

  describe "judge_model configuration" do
    it "defaults to gpt-5.4" do
      expect(described_class.judge_model).to eq("gpt-5.4")
    end

    it "can be overridden" do
      original = described_class.judge_model
      described_class.judge_model = "claude-opus-4-7"
      expect(described_class.judge_model).to eq("claude-opus-4-7")
    ensure
      described_class.judge_model = original
    end
  end
end
