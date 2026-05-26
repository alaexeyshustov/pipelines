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
    response = Struct.new(:content).new(response_content)
    judge_stub = Class.new do
      def with_model(_m) = self
      def ask(_msg) = nil
    end.new
    allow(judge_stub).to receive(:ask).and_return(response)
    allow(Evaluation::Judge::Agent).to receive(:create).and_return(judge_stub)
    judge_stub
  end

  describe "#evaluate" do
    let(:prompt) { create(:orchestration_prompt, name: agent_name, system_prompt: "You are a classifier.") }
    let(:dataset_sample) do
      create(:evaluation_dataset_sample,
             input: { "email" => "subject: Job offer" },
             expected_tool_calls: [ { "tool_name" => "classify_email", "arguments" => { "label" => "offer" }, "result" => "done" } ])
    end
    let(:sample) do
      create(:evaluation_sample,
             tool_calls: [ { "tool_name" => "classify_email", "arguments" => { "label" => "offer" } } ],
             output: "Classified.",
             prompt: prompt,
             dataset_sample: dataset_sample)
    end

    before do
      create(:evaluation_metric, agent_name: agent_name, name: "tool_call_accuracy", description: "Score tool call order.")
      create(:evaluation_metric, agent_name: agent_name, name: "output_quality", description: "Score output quality.")
    end

    it "returns per-metric scores with justifications" do
      stub_judge_agent
      results = eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
      expect(results.size).to eq(2)
      expect(results.first).to include(metric_name: "tool_call_accuracy", score: 4.0, justification: a_kind_of(String))
    end

    it "passes tool calls to the judge message" do
      judge_stub = stub_judge_agent
      eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
      expect(judge_stub).to have_received(:ask).with(including("classify_email"))
    end

    it "passes metric names to the judge message" do
      judge_stub = stub_judge_agent
      eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
      expect(judge_stub).to have_received(:ask).with(including("tool_call_accuracy").and(including("output_quality")))
    end

    context "when output is a structured hash" do
      let(:sample) do
        create(:evaluation_sample,
               tool_calls: [],
               output: { results: [ { id: "abc123", tags: [ "job", "application" ] } ] }.to_json,
               prompt: prompt,
               dataset_sample: dataset_sample)
      end

      it "serialises the output as valid JSON (not Ruby inspect) in the judge message" do
        judge_stub = stub_judge_agent
        eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
        expect(judge_stub).to have_received(:ask) do |message|
          expect(message).to include('"id"')
          expect(message).not_to include("=>")
        end
      end
    end

    context "when the judge agent returns unexpected content" do
      it "returns an empty array without raising" do
        judge_stub = Class.new do
          define_method(:with_model) { |_m| self }
          define_method(:ask) { |_msg| Struct.new(:content).new("not a hash") }
        end.new
        allow(Evaluation::Judge::Agent).to receive(:create).and_return(judge_stub)

        expect(eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)).to eq([])
      end
    end

    context "when both tool_calls and output are blank" do
      let(:sample) do
        create(:evaluation_sample, tool_calls: [], output: nil, prompt: prompt, dataset_sample: dataset_sample)
      end

      it "returns an empty array without raising" do
        expect(eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)).to eq([])
      end
    end

    context "when the judge returns a score outside 1–5" do
      it "drops the invalid entry and returns an empty array" do
        stub_judge_agent(scores: [ { "metric_name" => "tool_call_accuracy", "score" => 10, "justification" => "Way off." } ])
        expect(eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)).to eq([])
      end
    end

    context "when the prompt has an output_schema" do
      let(:output_schema) { { "type" => "object", "properties" => { "label" => { "type" => "string" } } } }
      let(:prompt) { create(:orchestration_prompt, name: agent_name, system_prompt: "You are a classifier.", output_schema: output_schema) }

      it "passes output_schema to the judge message" do
        judge_stub = stub_judge_agent
        eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
        expect(judge_stub).to have_received(:ask).with(including("output_schema"))
      end
    end

    context "when the prompt has no output_schema" do
      it "omits output_schema from the judge message" do
        judge_stub = stub_judge_agent
        eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
        expect(judge_stub).not_to have_received(:ask).with(including("output_schema"))
      end
    end

    context "when expected_tool_calls is nil on the dataset_sample" do
      let(:dataset_sample_without_expected) do
        create(:evaluation_dataset_sample,
               input: { "email" => "subject: Job offer" },
               expected_tool_calls: nil)
      end

      it "omits expected_tool_calls from the judge message" do
        judge_stub = stub_judge_agent
        eval_instance.evaluate(sample, dataset_sample_without_expected, agent_name: agent_name)
        expect(judge_stub).not_to have_received(:ask).with(including("expected_tool_calls"))
      end

      it "still calls the judge with input and actual tool calls" do
        judge_stub = stub_judge_agent
        eval_instance.evaluate(sample, dataset_sample_without_expected, agent_name: agent_name)
        expect(judge_stub).to have_received(:ask).with(including("classify_email"))
      end
    end

    context "when no active metrics exist" do
      before { Evaluation::Metric.update_all(active: false) }

      it "skips the judge and returns an empty array" do
        allow(Evaluation::Judge::Agent).to receive(:create)
        result = eval_instance.evaluate(sample, dataset_sample, agent_name: agent_name)
        expect(result).to eq([])
        expect(Evaluation::Judge::Agent).not_to have_received(:create)
      end
    end
  end

  describe "#evaluate_and_store" do
    let!(:evaluation_prompt) { Evaluation::Prompt.create!(name: agent_name, system_prompt: "You are a classifier.", user_prompt: "Classify: {{input}}") }
    let!(:evaluation_dataset) { Evaluation::Dataset.create!(name: "test_dataset") }
    let!(:evaluation_experiment) { Evaluation::Experiment.create!(name: "test_exp", dataset: evaluation_dataset, status: :pending, prompt: evaluation_prompt) }
    let!(:evaluation_dataset_sample) { Evaluation::DatasetSample.create!(dataset: evaluation_dataset, input: { "email" => "test" }) }
    let!(:evaluation_sample) do
      Evaluation::Sample.create!(
        experiment: evaluation_experiment,
        dataset_sample: evaluation_dataset_sample,
        prompt: evaluation_prompt,
        tool_calls: [],
        output: "classified"
      )
    end

    before do
      create(:evaluation_metric, agent_name: agent_name, name: "tool_call_accuracy", description: "Tool call accuracy.")
      create(:evaluation_metric, agent_name: agent_name, name: "output_quality", description: "Output quality.")
      stub_judge_agent(scores: [
        { "metric_name" => "tool_call_accuracy", "score" => 4, "justification" => "Good." },
        { "metric_name" => "output_quality",      "score" => 5, "justification" => "Excellent." }
      ])
    end

    it "creates one EvaluationResult per metric" do
      expect {
        eval_instance.evaluate_and_store(evaluation_experiment, evaluation_sample)
      }.to change(Evaluation::EvaluationResult, :count).by(2)
    end

    it "creates one Justification per metric" do
      expect {
        eval_instance.evaluate_and_store(evaluation_experiment, evaluation_sample)
      }.to change(Evaluation::Justification, :count).by(2)
    end

    it "stores scores between 1 and 5" do
      eval_instance.evaluate_and_store(evaluation_experiment, evaluation_sample)
      expect(Evaluation::EvaluationResult.last(2).map(&:score)).to all(be_between(1, 5))
    end

    it "links justifications to their evaluation results" do
      eval_instance.evaluate_and_store(evaluation_experiment, evaluation_sample)
      expect(Evaluation::Justification.last.evaluation_result).to be_a(Evaluation::EvaluationResult)
    end

    it "returns the created evaluation results" do
      results = eval_instance.evaluate_and_store(evaluation_experiment, evaluation_sample)

      expect(results).to all(be_a(Evaluation::EvaluationResult))
      expect(results.map(&:score)).to eq([ 4.0, 5.0 ])
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
