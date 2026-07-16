
require "rails_helper"

RSpec.describe Evaluation::Wizard::Step2Form do
  subject(:form) { described_class.new(draft_payload: payload) }

  let(:payload) { { "agent_name" => "Emails::ClassifyAgent" } }


  describe "#agent_name" do
    it "returns the agent_name from payload" do
      expect(form.agent_name).to eq("Emails::ClassifyAgent")
    end
  end

  describe "#metrics" do
    it "returns metrics for the agent ordered by name" do
      m1 = create(:evaluation_metric, agent_name: "Emails::ClassifyAgent", name: "relevance")
      m2 = create(:evaluation_metric, agent_name: "Emails::ClassifyAgent", name: "accuracy")
      expect(form.metrics.to_a).to eq([ m2, m1 ])
    end

    it "does not return metrics for other agents" do
      create(:evaluation_metric, agent_name: "Other::Agent", name: "accuracy")
      expect(form.metrics).to be_empty
    end
  end

  context "with empty payload" do
    subject(:form) { described_class.new(draft_payload: {}) }

    it "returns nil for agent_name" do
      expect(form.agent_name).to be_nil
    end
  end
end
