require "rails_helper"

RSpec.describe Evaluation::Tasks do
  let(:out) { StringIO.new }
  let(:agent_name) { "Emails::ClassifyAgent" }

  describe ".extract_metrics" do
    before do
      allow(Evaluation::MetricExtractor).to receive(:call).with(agent_name)
                                                          .and_return([ { "name" => "tone", "description" => "Polite" } ])
    end

    it "prints each candidate metric" do
      described_class.extract_metrics(agent_name, out:)
      expect(out.string).to eq("name: tone\ndescription: Polite\n---\n")
    end

    it "requires an agent name" do
      expect { described_class.extract_metrics(nil, out:) }
        .to raise_error(ArgumentError, "Usage: rake evaluation:extract_metrics[AgentName]")
    end
  end

  describe ".seed_metrics" do
    before do
      allow(Evaluation::MetricSeeder).to receive(:call).with(agent_name:)
                                                       .and_return(Evaluation::MetricSeeder::Result.new(created: 2, updated: 1))
    end

    it "prints the counts" do
      described_class.seed_metrics(agent_name, out:)
      expect(out.string).to eq("Seeded metrics for #{agent_name}: 2 created, 1 updated.\n")
    end
  end
end
