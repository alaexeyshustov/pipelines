# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::WizardDraft do
  describe "validations" do
    it "is valid with required attributes" do
      draft = build(:evaluation_wizard_draft)
      expect(draft).to be_valid
    end

    it "requires session_token" do
      draft = build(:evaluation_wizard_draft, session_token: nil)
      expect(draft).not_to be_valid
      expect(draft.errors[:session_token]).to be_present
    end

    it "enforces uniqueness of session_token" do
      create(:evaluation_wizard_draft, session_token: "abc123")
      duplicate = build(:evaluation_wizard_draft, session_token: "abc123")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:session_token]).to be_present
    end

    it "requires step to be between 1 and 4" do
      draft = build(:evaluation_wizard_draft, step: 5)
      expect(draft).not_to be_valid
      expect(draft.errors[:step]).to be_present
    end

    it "accepts steps 1 through 4" do
      (1..4).each do |s|
        draft = build(:evaluation_wizard_draft, step: s)
        expect(draft).to be_valid, "expected step #{s} to be valid"
      end
    end
  end

  describe ".find_or_create_for_token" do
    it "creates a new draft when none exists" do
      expect { described_class.find_or_create_for_token("new_token") }.to change(described_class, :count).by(1)
    end

    it "returns the existing draft on subsequent calls" do
      first  = described_class.find_or_create_for_token("same_token")
      second = described_class.find_or_create_for_token("same_token")
      expect(second.id).to eq(first.id)
    end
  end

  describe ".cleanup_expired" do
    it "deletes drafts older than 24 hours" do
      old_draft   = create(:evaluation_wizard_draft, session_token: "old", updated_at: 25.hours.ago)
      fresh_draft = create(:evaluation_wizard_draft, session_token: "fresh")

      described_class.cleanup_expired

      expect(described_class.exists?(old_draft.id)).to be false
      expect(described_class.exists?(fresh_draft.id)).to be true
    end
  end

  describe "#advance!" do
    let(:draft) { create(:evaluation_wizard_draft, step: 1, payload: { "existing_key" => "value" }) }

    it "advances the step" do
      draft.advance!(2, { new_key: "new_value" })
      expect(draft.reload.step).to eq(2)
    end

    it "merges payload updates" do
      draft.advance!(2, { new_key: "new_value" })
      expect(draft.reload.payload).to include("existing_key" => "value", "new_key" => "new_value")
    end

    it "stringifies symbol keys in payload_updates" do
      draft.advance!(2, { symbol_key: "val" })
      expect(draft.reload.payload).to have_key("symbol_key")
    end
  end

  describe "#merge_payload!" do
    let(:draft) { create(:evaluation_wizard_draft, step: 2, payload: { "existing" => "data" }) }

    it "merges updates into payload without changing the step" do
      draft.merge_payload!({ "new_key" => "new_val" })
      expect(draft.reload.payload).to include("existing" => "data", "new_key" => "new_val")
      expect(draft.reload.step).to eq(2)
    end

    it "stringifies symbol keys" do
      draft.merge_payload!({ sym_key: "val" })
      expect(draft.reload.payload).to have_key("sym_key")
    end
  end

  describe "#payload_for_step" do
    let(:draft) { build(:evaluation_wizard_draft, payload: { "metrics" => [ { "name" => "accuracy" } ] }) }

    it "returns the value for a string key" do
      expect(draft.payload_for_step("metrics")).to eq([ { "name" => "accuracy" } ])
    end

    it "returns the value for a symbol key" do
      expect(draft.payload_for_step(:metrics)).to eq([ { "name" => "accuracy" } ])
    end

    it "returns nil when payload is nil" do
      draft.payload = nil
      expect(draft.payload_for_step(:metrics)).to be_nil
    end
  end
end
