require "rails_helper"

RSpec.describe Evaluation::Evaluators::LLMJudgeEval do
  subject(:eval_instance) { described_class.new }

  let(:agent_name) { "Emails::ClassifyAgent" }

  def stub_judge_agent(scores: nil)
    scores ||= [
      { "metric_name" => "tool_call_accuracy", "score" => 4, "justification" => "Correct tool called." },
      { "metric_name" => "output_quality",      "score" => 5, "justification" => "Clear output." }
    ]
    response_content = { "evaluations" => scores }
    agent_double = instance_double(Evaluation::Judge::Agent)
    allow(agent_double).to receive_messages(with_model: agent_double, ask: double(content: response_content))
    allow(Evaluation::Judge::Agent).to receive(:create).and_return(agent_double)
    agent_double
  end

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
    let(:prompt_double) { instance_double(Evaluation::Prompt, system_prompt: "You are a classifier.") }
    let(:runner_result) do
      prediction = { tool_calls: [ { tool_name: "classify_email", arguments: { label: "offer" } } ], output: "Classified." }.to_json
      instance_double(
        Evaluation::RunnerResult,
        prediction: prediction,
        prompt: prompt_double,
        dataset_record: instance_double(Evaluation::DatasetRecord, recordable: recordable)
      )
    end

    before do
      create(:evaluation_metric, agent_name: agent_name, name: "tool_call_accuracy", description: "Score tool call order.")
      create(:evaluation_metric, agent_name: agent_name, name: "output_quality", description: "Score output quality.")

      allow(Evaluation::ToolCallExtractor).to receive(:call).and_return(
        [ { tool_name: "classify_email", arguments: { label: "offer" }, result: "done" } ]
      )
    end

    context "when recordable does not implement the duck-type interface" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "raises ArgumentError with a descriptive message" do
        chat = create(:chat)
        runner_result = instance_double(Evaluation::RunnerResult, prediction: "{}")
        expect { eval_instance.evaluate(runner_result, chat) }.to raise_error(ArgumentError, /#input.*#step_action|#step_action.*#input/)
      end
    end

    it "returns per-metric scores with justifications" do
      stub_judge_agent
      results = eval_instance.evaluate(runner_result, recordable)
      expect(results.size).to eq(2)
      expect(results.first).to include(metric_name: "tool_call_accuracy", score: 4.0, justification: a_kind_of(String))
    end

    it "passes tool calls to the judge message" do
      agent_double = stub_judge_agent
      eval_instance.evaluate(runner_result, recordable)
      expect(agent_double).to have_received(:ask).with(including("classify_email"))
    end

    it "passes metric names to the judge message" do
      agent_double = stub_judge_agent
      eval_instance.evaluate(runner_result, recordable)
      expect(agent_double).to have_received(:ask).with(including("tool_call_accuracy").and(including("output_quality")))
    end

    context "when output is a hash (structured JSON result)" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:runner_result) do
        prediction = {
          tool_calls: [],
          output: { results: [ { id: "abc123", tags: [ "job", "application" ] } ] }
        }.to_json
        instance_double(
          Evaluation::RunnerResult,
          prediction: prediction,
          prompt: prompt_double,
          dataset_record: instance_double(Evaluation::DatasetRecord, recordable: recordable)
        )
      end

      it "serialises the output as valid JSON (not Ruby inspect) in the judge message" do
        agent_double = stub_judge_agent
        eval_instance.evaluate(runner_result, recordable)
        expect(agent_double).to have_received(:ask) do |message|
          expect(message).to include('"id"')
          expect(message).not_to include("=>")
        end
      end
    end

    context "when the judge agent returns unexpected content" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "returns an empty array without raising" do
        agent_double = instance_double(Evaluation::Judge::Agent)
        allow(agent_double).to receive_messages(with_model: agent_double, ask: double(content: "not a hash"))
        allow(Evaluation::Judge::Agent).to receive(:create).and_return(agent_double)

        expect(eval_instance.evaluate(runner_result, recordable)).to eq([])
      end
    end

    context "when prediction is nil" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:runner_result) do
        instance_double(
          Evaluation::RunnerResult,
          prediction: nil,
          prompt: prompt_double,
          dataset_record: instance_double(Evaluation::DatasetRecord, recordable: recordable)
        )
      end

      it "returns an empty array without raising" do
        expect(eval_instance.evaluate(runner_result, recordable)).to eq([])
      end
    end

    context "when the judge returns a score outside 1–5" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "drops the invalid entry and returns an empty array" do
        stub_judge_agent(scores: [ { "metric_name" => "tool_call_accuracy", "score" => 10, "justification" => "Way off." } ])
        expect(eval_instance.evaluate(runner_result, recordable)).to eq([])
      end
    end

    context "when no active metrics exist" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before { Evaluation::Metric.update_all(active: false) }

      it "skips the judge and returns an empty array" do
        allow(Evaluation::Judge::Agent).to receive(:create)
        result = eval_instance.evaluate(runner_result, recordable)
        expect(result).to eq([])
        expect(Evaluation::Judge::Agent).not_to have_received(:create)
      end
    end
  end

  describe "#evaluate_and_store" do
    let!(:evaluation_dataset) { Evaluation::Dataset.create!(name: "test_dataset") }
    let!(:evaluation_prompt) { Evaluation::Prompt.create!(name: agent_name, system_prompt: "You are a classifier.", user_prompt: "Classify: {{input}}") }
    let!(:evaluation_experiment) { Evaluation::Experiment.create!(name: "test_exp", dataset: evaluation_dataset, status: :pending, prompt: evaluation_prompt, runner_class: "Evaluation::Runners::StubbedAgentRun", evaluator_classes: [ "Evaluation::Evaluators::LLMJudgeEval" ]) }
    let!(:evaluation_dataset_record) do
      classify_agent = create(:orchestration_agent, name: agent_name)
      action = create(:orchestration_action, kind: :agent, agent: classify_agent)
      step_action = create(:orchestration_step_action, action: action)
      action_run = create(:orchestration_action_run, step_action: step_action, status: "completed")
      Evaluation::DatasetRecord.create!(dataset: evaluation_dataset, recordable: action_run)
    end
    let!(:evaluation_runner_result) do
      Evaluation::RunnerResult.create!(
        experiment: evaluation_experiment,
        dataset_record: evaluation_dataset_record,
        prompt: evaluation_prompt,
        prediction: { tool_calls: [], output: "classified" }.to_json,
        runner_class: "Evaluation::Runners::StubbedAgentRun"
      )
    end

    before do
      create(:evaluation_metric, agent_name: agent_name, name: "tool_call_accuracy", description: "Tool call accuracy.")
      create(:evaluation_metric, agent_name: agent_name, name: "output_quality", description: "Output quality.")
      allow(Evaluation::ToolCallExtractor).to receive(:call).and_return([])
      stub_judge_agent(scores: [
        { "metric_name" => "tool_call_accuracy", "score" => 4, "justification" => "Good." },
        { "metric_name" => "output_quality",      "score" => 5, "justification" => "Excellent." }
      ])
    end

    it "creates one EvaluationResult per metric" do
      expect {
        eval_instance.evaluate_and_store(evaluation_experiment, evaluation_runner_result)
      }.to change(Evaluation::EvaluationResult, :count).by(2)
    end

    it "creates one Justification per metric" do
      expect {
        eval_instance.evaluate_and_store(evaluation_experiment, evaluation_runner_result)
      }.to change(Evaluation::Justification, :count).by(2)
    end

    it "stores scores between 1 and 5" do
      eval_instance.evaluate_and_store(evaluation_experiment, evaluation_runner_result)
      expect(Evaluation::EvaluationResult.last(2).map(&:score)).to all(be_between(1, 5))
    end

    it "links justifications to their evaluation results" do
      eval_instance.evaluate_and_store(evaluation_experiment, evaluation_runner_result)
      expect(Evaluation::Justification.last.evaluation_result).to be_a(Evaluation::EvaluationResult)
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
