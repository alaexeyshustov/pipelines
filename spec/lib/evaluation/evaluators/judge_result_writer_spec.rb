require "rails_helper"

RSpec.describe Evaluation::Evaluators::JudgeResultWriter do
  subject(:call_writer) do
    described_class.call(
      metric_results: metric_results,
      experiment: experiment,
      dataset_sample: dataset_sample,
      sample: sample,
      evaluator_class: "Evaluation::Evaluators::LLMJudgeEval"
    )
  end

  let(:experiment) { create(:evaluation_experiment) }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset) }
  let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample) }
  let(:metric_results) do
    [
      { metric_name: "tool_call_accuracy", score: 4, justification: "Good." },
      { metric_name: "output_quality", score: 5, justification: "Excellent." }
    ]
  end

  it "creates one EvaluationResult per metric" do
    expect { call_writer }.to change(Evaluation::EvaluationResult, :count).by(2)
  end

  it "creates one Justification per metric" do
    expect { call_writer }.to change(Evaluation::Justification, :count).by(2)
  end

  it "stores the given evaluator_class on each result" do
    call_writer
    expect(Evaluation::EvaluationResult.last(2).map(&:evaluator_class))
      .to all(eq("Evaluation::Evaluators::LLMJudgeEval"))
  end

  it "stores the score and dataset/sample associations on each result" do
    call_writer
    result = Evaluation::EvaluationResult.order(:id).first
    expect(result.score).to eq(4.0)
    expect(result.dataset_sample).to eq(dataset_sample)
    expect(result.sample).to eq(sample)
  end

  it "links justifications to their evaluation results with matching metric data" do
    call_writer
    justification = Evaluation::Justification.joins(:evaluation_result)
                                              .find_by(metric_name: "tool_call_accuracy")
    expect(justification.justification).to eq("Good.")
    expect(justification.evaluation_result.score).to eq(4.0)
  end

  it "returns the created evaluation results in insertion order" do
    results = call_writer
    expect(results).to all(be_a(Evaluation::EvaluationResult))
    expect(results.map(&:score)).to eq([ 4.0, 5.0 ])
  end
end
