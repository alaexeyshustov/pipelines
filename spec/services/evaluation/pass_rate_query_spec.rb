require "rails_helper"

RSpec.describe Evaluation::PassRateQuery do
  let(:experiment) { create(:evaluation_experiment) }

  def graded(metric_name, passed)
    result = create(:evaluation_evaluation_result, experiment: experiment, passed: passed)
    Evaluation::Justification.create!(evaluation_result: result, metric_name: metric_name, justification: "j")
  end

  before do
    graded("accuracy", true)
    graded("accuracy", false)
    graded("tone", true)
    graded("tone", nil)
  end

  it "returns the share of passed results, ignoring results without a verdict" do
    expect(described_class.call(experiment_ids: [ experiment.id ])).to eq(experiment.id => 2.0 / 3)
  end

  it "omits experiments without verdicts" do
    other = create(:evaluation_experiment)
    expect(described_class.call(experiment_ids: [ other.id ])).to eq({})
  end

  it "returns pass rates per metric" do
    expect(Evaluation::MetricPassRateQuery.call(experiment: experiment)).to eq("accuracy" => 0.5, "tone" => 1.0)
  end
end
