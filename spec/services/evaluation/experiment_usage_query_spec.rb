require "rails_helper"

RSpec.describe Evaluation::ExperimentUsageQuery do
  let(:experiment) { create(:evaluation_experiment) }
  let(:other) { create(:evaluation_experiment) }

  def usage(owner, attrs = {})
    RubyLLM::ActiveRecord::Usage.create!({ operation: "chat", provider: "openai", model: "gpt-5.4", status: "succeeded",
                                           input_tokens: 100, output_tokens: 50, total_cost: 0.01, owner: owner }.merge(attrs))
  end

  it "sums tokens, cost and calls per experiment and counts models" do
    usage(experiment)
    usage(experiment, model: "mistral-large-latest", input_tokens: 10, output_tokens: 5, total_cost: 0.002)
    usage(other, total_cost: 1)

    result = described_class.call(experiment_ids: [ experiment.id, other.id ])

    expect(result[experiment.id]).to have_attributes(
      input_tokens: 110, output_tokens: 55, total_tokens: 165, calls: 2, cost: BigDecimal("0.012"),
      models: { "gpt-5.4" => 1, "mistral-large-latest" => 1 }
    )
    expect(result[other.id].cost).to eq(1)
  end

  it "ignores failed attempts, other owners and unpriced rows' cost" do
    usage(experiment, status: "failed")
    usage(experiment, total_cost: nil)
    usage(nil)

    expect(described_class.call(experiment_ids: [ experiment.id ])[experiment.id])
      .to have_attributes(calls: 1, cost: 0, input_tokens: 100)
  end

  it "returns an empty usage for experiments without rows" do
    expect(described_class.call(experiment_ids: [ experiment.id ])[experiment.id]).to eq(described_class::EMPTY)
  end
end
