# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::WizardDraftCleanupJob do
  describe "#perform" do
    it "deletes drafts older than 24 hours" do
      old_draft = create(:evaluation_wizard_draft, session_token: "old", updated_at: 25.hours.ago)

      described_class.perform_now

      expect(Evaluation::WizardDraft.exists?(old_draft.id)).to be false
    end

    it "leaves drafts updated within the last 24 hours intact" do
      fresh_draft = create(:evaluation_wizard_draft, session_token: "fresh")

      described_class.perform_now

      expect(Evaluation::WizardDraft.exists?(fresh_draft.id)).to be true
    end

    it "logs the number of deleted drafts" do
      create(:evaluation_wizard_draft, session_token: "old_one", updated_at: 25.hours.ago)

      allow(Rails.logger).to receive(:info)
      described_class.perform_now

      expect(Rails.logger).to have_received(:info).with(/WizardDraftCleanupJob.*1/)
    end
  end
end
