# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::SyntheticRecord do
  describe "validations" do
    it "is valid with required attributes" do
      record = build(:evaluation_synthetic_record)
      expect(record).to be_valid
    end

    it "requires agent_name" do
      record = build(:evaluation_synthetic_record, agent_name: nil)
      expect(record).not_to be_valid
      expect(record.errors[:agent_name]).to be_present
    end

    it "requires input" do
      record = build(:evaluation_synthetic_record, input: nil)
      expect(record).not_to be_valid
      expect(record.errors[:input]).to be_present
    end
  end

  describe "#step_action" do
    subject(:step_action) { described_class.new(agent_name: "Emails::ClassifyAgent", input: {}).step_action }

    it "returns a SyntheticStepAction" do
      expect(step_action).to be_a(Evaluation::SyntheticStepAction)
    end

    it "exposes agent_class equal to agent_name" do
      expect(step_action.action.agent_class).to eq("Emails::ClassifyAgent")
    end

    it "reports agent? as false" do
      expect(step_action.action.agent?).to be false
    end

    it "returns nil for agent" do
      expect(step_action.action.agent).to be_nil
    end
  end

  describe "#chat" do
    it "returns nil" do
      expect(described_class.new.chat).to be_nil
    end
  end
end
