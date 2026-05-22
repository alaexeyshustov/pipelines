# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::WizardForm do
  subject(:form) { described_class.new(wizard_token: token) }

  let(:token) { "abc123" }

  describe "draft creation" do
    it "creates a new draft for an unknown token" do
      expect { form.step_form(1) }.to change(Evaluation::WizardDraft, :count).by(1)
    end

    it "reuses an existing draft for a known token" do
      create(:evaluation_wizard_draft, session_token: token)
      expect { form.step_form(1) }.not_to change(Evaluation::WizardDraft, :count)
    end
  end

  describe "#step" do
    before { create(:evaluation_wizard_draft, session_token: token, step: 2) }

    it "returns the draft step when no step_param given" do
      expect(described_class.new(wizard_token: token).step).to eq(2)
    end

    it "returns the step_param when provided" do
      expect(described_class.new(wizard_token: token, step_param: 3).step).to eq(3)
    end

    it "clamps step_param below 1 to 1" do
      expect(described_class.new(wizard_token: token, step_param: 0).step).to eq(1)
    end

    it "clamps step_param above WIZARD_STEPS to WIZARD_STEPS" do
      expect(described_class.new(wizard_token: token, step_param: 99).step).to eq(Evaluation::WizardForm::WIZARD_STEPS)
    end
  end

  describe "#advance!" do
    context "when advancing from step 1" do
      before { create(:evaluation_wizard_draft, session_token: token, step: 1) }

      it "advances the draft to the next step and persists the payload" do
        form.advance!(1, { "agent_name" => "MyAgent" })
        draft = Evaluation::WizardDraft.find_by(session_token: token)
        expect(draft.step).to eq(2)
        expect(draft.payload["agent_name"]).to eq("MyAgent")
      end
    end

    context "when advancing from step 2 with active metrics" do
      before do
        create(:evaluation_metric, agent_name: "MyAgent", active: true)
        create(:evaluation_wizard_draft, session_token: token, step: 2,
               payload: { "agent_name" => "MyAgent" })
      end

      it "returns true and advances the draft" do
        result = form.advance!(2, {})
        expect(result).to be(true)
        expect(Evaluation::WizardDraft.find_by(session_token: token).step).to eq(3)
      end
    end

    context "when advancing from step 2 with no active metrics" do
      before do
        create(:evaluation_wizard_draft, session_token: token, step: 2,
               payload: { "agent_name" => "MyAgent" })
      end

      it "returns false" do
        result = form.advance!(2, {})
        expect(result).to be(false)
      end

      it "adds a base error" do
        form.advance!(2, {})
        expect(form.errors[:base]).to be_present
      end

      it "does not advance the draft step" do
        form.advance!(2, {})
        expect(Evaluation::WizardDraft.find_by(session_token: token).step).to eq(2)
      end
    end
  end

  describe "#complete!" do
    let!(:dataset) { create(:evaluation_dataset) }
    let!(:prompt)  { create(:orchestration_prompt) }

    before { create(:evaluation_metric, agent_name: prompt.name)
create(:evaluation_wizard_draft,
             session_token: token,
             step: 4,
             payload: { "agent_name" => prompt.name, "experiment_name" => "Final", "prompt_id" => prompt.id.to_s, "dataset_id" => dataset.id.to_s })
      allow(Evaluation::ExperimentJob).to receive(:perform_later)
     }


    it "creates and returns an experiment" do
      experiment = form.complete!
      expect(experiment).to be_a(Evaluation::Experiment)
      expect(experiment).to be_persisted
    end
  end

  describe "#valid?" do
    context "when dataset_id is present in the draft payload" do
      before do
        create(:evaluation_wizard_draft, session_token: token,
               payload: { "experiment_name" => "Eval", "dataset_id" => "7" })
      end

      it "returns true" do
        expect(form.valid?).to be true
      end
    end

    context "when dataset_id is missing from the draft payload" do
      before do
        create(:evaluation_wizard_draft, session_token: token,
               payload: { "experiment_name" => "Eval" })
      end

      it "returns false" do
        expect(form.valid?).to be false
      end

      it "adds a meaningful error" do
        form.valid?
        expect(form.errors[:dataset]).to be_present
      end
    end
  end

  describe "#complete?" do
    before { create(:evaluation_wizard_draft, session_token: token, step: 1) }

    it "returns true when step equals WIZARD_STEPS" do
      form = described_class.new(wizard_token: token, step_param: Evaluation::WizardForm::WIZARD_STEPS)
      expect(form.complete?).to be true
    end

    it "returns true when step exceeds WIZARD_STEPS (clamped edge)" do
      form = described_class.new(wizard_token: token, step_param: 99)
      expect(form.complete?).to be true
    end

    it "returns false when step is before the last step" do
      form = described_class.new(wizard_token: token, step_param: 3)
      expect(form.complete?).to be false
    end
  end

  describe "#step_form" do
    let(:payload) { { "agent_name" => "Emails::ClassifyAgent", "dataset_id" => "7" } }

    before do
      create(:evaluation_wizard_draft, session_token: token, step: 1, payload: payload)
    end

    it "returns Step1Form for step 1" do
      expect(form.step_form(1)).to be_a(Evaluation::Wizard::Step1Form)
    end

    it "returns Step2Form for step 2" do
      expect(form.step_form(2)).to be_a(Evaluation::Wizard::Step2Form)
    end

    it "returns Step3Form for step 3 with draft_token set" do
      step_form = form.step_form(3)
      expect(step_form).to be_a(Evaluation::Wizard::Step3Form)
      expect(step_form.draft_token).to eq(token)
    end

    it "returns Step4Form for step 4" do
      expect(form.step_form(4)).to be_a(Evaluation::Wizard::Step4Form)
    end

    context "when step 1" do
      it "populates agent_name from the draft payload" do
        expect(form.step_form(1).agent_name).to eq("Emails::ClassifyAgent")
      end
    end
  end
end
