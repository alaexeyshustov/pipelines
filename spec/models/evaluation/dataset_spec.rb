# frozen_string_literal: true

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
end
