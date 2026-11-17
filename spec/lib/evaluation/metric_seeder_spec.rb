require "rails_helper"

RSpec.describe Evaluation::MetricSeeder do
  subject(:result) { described_class.call(agent_name:) }

  let(:agent_name) { "Emails::ClassifyAgent" }

  before do
    create(:evaluation_metric, agent_name:, name: "accuracy", description: "old")
    allow(Evaluation::MetricExtractor).to receive(:call).with(agent_name).and_return(
      [ { "name" => "accuracy", "description" => "Labels match" }, { "name" => "tone", "description" => "Polite" } ]
    )
  end

  it "counts created and updated metrics" do
    expect(result).to have_attributes(created: 1, updated: 1)
  end

  it "updates the description of an existing metric" do
    result
    expect(Evaluation::Metric.find_by!(agent_name:, name: "accuracy").description).to eq("Labels match")
  end

  it "creates a new metric" do
    result
    expect(Evaluation::Metric.find_by(agent_name:, name: "tone")).to have_attributes(description: "Polite")
  end
end
