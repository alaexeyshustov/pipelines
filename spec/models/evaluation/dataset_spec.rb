
require "rails_helper"

RSpec.describe Evaluation::Dataset do
  describe ".for_agent" do
    let!(:agent_dataset)  { create(:evaluation_dataset, agent_name: "Emails::ClassifyAgent") }
    let!(:other_dataset)  { create(:evaluation_dataset, agent_name: "Emails::OtherAgent") }
    let!(:unnamed_dataset) { create(:evaluation_dataset, agent_name: nil) }

    it "returns datasets matching the given agent name" do
      expect(described_class.for_agent("Emails::ClassifyAgent")).to include(agent_dataset)
    end

    it "excludes datasets with a different agent name" do
      expect(described_class.for_agent("Emails::ClassifyAgent")).not_to include(other_dataset)
    end

    it "excludes datasets with no agent name" do
      expect(described_class.for_agent("Emails::ClassifyAgent")).not_to include(unnamed_dataset)
    end
  end

  describe ".with_record_counts" do
    before do
      create(:evaluation_dataset, name: "Alpha")
      dataset_b = create(:evaluation_dataset, name: "Bravo")
      dataset_c = create(:evaluation_dataset, name: "Charlie")
      create_list(:evaluation_dataset_sample, 3, dataset: dataset_c)
      create(:evaluation_dataset_sample, dataset: dataset_b)
    end

    it "returns the exact record_count per dataset" do
      counts = described_class.with_record_counts.to_h { |d| [ d.name, d.record_count.to_i ] }
      expect(counts).to eq("Alpha" => 0, "Bravo" => 1, "Charlie" => 3)
    end

    it "orders datasets by name" do
      expect(described_class.with_record_counts.map(&:name)).to eq(%w[Alpha Bravo Charlie])
    end
  end
end
