require "rails_helper"

RSpec.describe Evaluation::Grader::ResultWriter do
  subject(:write) do
    described_class.call(grades: grades, experiment: experiment, dataset_sample: dataset_sample, sample: sample)
  end

  let(:experiment) { create(:evaluation_experiment) }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset) }
  let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample) }
  let(:grades) do
    [
      Evaluation::Grade.new(metric_name: "accuracy", score: 0.9, raw: { type: "probability", probability: 0.9 },
                            confidence: nil, passed: true, justification: "Good.", tokens: nil, cost: nil),
      Evaluation::Grade.new(metric_name: "quality", score: 0.5, raw: { type: "score", score: 1.0 },
                            confidence: 0.7, passed: false, justification: "Meh.", tokens: nil, cost: nil)
    ]
  end

  it "creates one result and one justification per grade" do
    expect { write }.to change(Evaluation::EvaluationResult, :count).by(2)
                    .and change(Evaluation::Justification, :count).by(2)
  end

  it "stores the normalized score, raw answer, confidence and passed" do
    results = write
    expect(results.first).to have_attributes(
      score: 0.9, raw: { "type" => "probability", "probability" => 0.9 }, confidence: nil, passed: true,
      evaluator_class: "Evaluation::Grader", experiment: experiment, dataset_sample: dataset_sample, sample: sample
    )
    expect(results.last).to have_attributes(score: 0.5, confidence: 0.7, passed: false)
  end

  it "links justifications to their results by metric name" do
    results = write
    expect(results.map { |r| r.justifications.pick(:metric_name, :justification) })
      .to eq([ [ "accuracy", "Good." ], [ "quality", "Meh." ] ])
  end

  it "writes nothing for an empty grade list" do
    expect(described_class.call(grades: [], experiment: experiment, dataset_sample: dataset_sample, sample: sample))
      .to eq([])
  end

  it "rolls back all rows when a justification is invalid" do
    grades[1] = grades[1].with(justification: nil)
    expect { write }.to raise_error(ActiveRecord::ActiveRecordError)
    expect(Evaluation::EvaluationResult.count).to eq(0)
  end
end
