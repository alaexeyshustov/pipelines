# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::AgentCatalog do
  describe ".find" do
    let!(:agent) do
      create(:orchestration_agent, name: "Emails::ClassifyAgent", model: "gpt-5.4",
             prompt: "Classify this email.", output_schema: { "type" => "object" })
    end

    it "returns a Metadata DTO when the agent exists" do
      expect(described_class.find(agent.name)).to be_a(described_class::Metadata)
    end

    it "carries over the agent's attributes" do
      metadata = described_class.find(agent.name)

      expect(metadata).to have_attributes(
        name: "Emails::ClassifyAgent",
        model: "gpt-5.4",
        prompt: "Classify this email.",
        output_schema: { "type" => "object" }
      )
    end

    it "returns nil when the agent does not exist" do
      expect(described_class.find("NonExistentAgent")).to be_nil
    end
  end
end
