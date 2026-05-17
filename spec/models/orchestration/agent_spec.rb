# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::Agent do
  subject(:agent) { build(:orchestration_agent) }

  it "is valid with valid attributes" do
    expect(agent).to be_valid
  end

  describe "associations" do
    it "exposes actions that reference it" do
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      action = create(:orchestration_action, kind: :agent, agent: agent)
      expect(agent.actions).to include(action)
    end

    it "does not include actions for other agents" do
      agent = create(:orchestration_agent, name: "Emails::ClassifyAgent")
      other_agent = create(:orchestration_agent, name: "Records::StoreAgent")
      create(:orchestration_action, kind: :agent, agent: other_agent)
      expect(agent.actions).to be_empty
    end
  end

  describe "validations" do
    it "requires name" do
      agent.name = nil
      expect(agent).not_to be_valid
      expect(agent.errors[:name]).to be_present
    end

    it "requires unique name" do
      create(:orchestration_agent, name: "Emails::ClassifyAgent")
      duplicate = build(:orchestration_agent, name: "Emails::ClassifyAgent")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it "accepts blank tools" do
      agent.tools = []
      expect(agent).to be_valid
    end

    it "rejects tools outside allowed namespaces" do
      agent.tools = [ "File" ]
      expect(agent).not_to be_valid
      expect(agent.errors[:tools].first).to include("outside allowed namespaces")
    end

    it "rejects unknown constants within allowed namespaces" do
      agent.tools = [ "Records::DoesNotExist" ]
      expect(agent).not_to be_valid
      expect(agent.errors[:tools]).to be_present
    end

    it "accepts valid tool constants" do
      agent.tools = [ "Emails::ClassifyAgent" ]
      expect(agent).to be_valid
    end
  end

  describe "defaults" do
    it "defaults enabled to true" do
      expect(agent.enabled).to be true
    end
  end

  describe "scopes" do
    let!(:enabled_agent) { create(:orchestration_agent, name: "Emails::ClassifyAgent", enabled: true) }
    let!(:disabled_agent) { create(:orchestration_agent, name: "Records::StoreAgent", enabled: false) }

    it "returns only enabled agents" do
      expect(described_class.enabled).to include(enabled_agent)
      expect(described_class.enabled).not_to include(disabled_agent)
    end
  end

  describe ".available_tools" do
    it "returns tool class name strings from app/tools/" do
      tools = described_class.available_tools
      expect(tools).to include("Emails::GetTool", "Records::ReadRowsTool")
    end

    it "only includes tools from allowed namespaces" do
      namespaces = described_class.available_tools.map { |t| t.split("::").first }.uniq
      expect(Orchestration::Agent::ALLOWED_TOOL_NAMESPACES).to include(*namespaces)
    end

    it "returns tools in sorted order" do
      tools = described_class.available_tools
      expect(tools).to eq(tools.sort)
    end
  end

  describe "#destroy" do
    let!(:persisted_agent) { create(:orchestration_agent, name: "Emails::ClassifyAgent") }

    context "when not referenced by any action" do
      it "can be destroyed" do
        expect { persisted_agent.destroy }.to change(described_class, :count).by(-1)
      end
    end

    context "when referenced by an action" do
      before { create(:orchestration_action, kind: :agent, agent: persisted_agent) }

      it "cannot be destroyed" do
        persisted_agent.destroy
        expect(persisted_agent.errors[:base]).to be_present
      end

      it "is not deleted from the database" do
        expect { persisted_agent.destroy }.not_to change(described_class, :count)
      end
    end
  end
end
