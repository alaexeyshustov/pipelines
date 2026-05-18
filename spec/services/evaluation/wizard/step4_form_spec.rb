# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::Step4Form do
  subject(:form) { described_class.new(draft_payload: payload) }

  let(:prompt)  { create(:orchestration_prompt, name: "Emails::ClassifyAgent", version: 2) }
  let(:dataset) { create(:evaluation_dataset, name: "emails_dataset") }
  let(:payload) do
    {
      "agent_name"      => "Emails::ClassifyAgent",
      "prompt_id"       => prompt.id.to_s,
      "experiment_name" => "My Eval",
      "dataset_id"      => dataset.id.to_s
    }
  end


  describe "#agent_name" do
    it "returns the agent_name from payload" do
      expect(form.agent_name).to eq("Emails::ClassifyAgent")
    end
  end

  describe "#experiment_name" do
    it "returns the experiment_name from payload" do
      expect(form.experiment_name).to eq("My Eval")
    end
  end

  describe "#prompt" do
    it "returns the Prompt record matching prompt_id" do
      expect(form.prompt).to eq(prompt)
    end

    it "returns nil when prompt_id is absent" do
      form_no_prompt = described_class.new(draft_payload: payload.merge("prompt_id" => nil))
      expect(form_no_prompt.prompt).to be_nil
    end
  end

  describe "#dataset" do
    it "returns the Dataset record matching dataset_id" do
      expect(form.dataset).to eq(dataset)
    end

    it "returns nil when dataset_id is absent" do
      form_no_dataset = described_class.new(draft_payload: payload.merge("dataset_id" => nil))
      expect(form_no_dataset.dataset).to be_nil
    end
  end

  describe "#metrics_count" do
    it "returns count of active metrics for the agent" do
      create(:evaluation_metric, agent_name: "Emails::ClassifyAgent", active: true)
      create(:evaluation_metric, agent_name: "Emails::ClassifyAgent", active: true)
      create(:evaluation_metric, agent_name: "Emails::ClassifyAgent", active: false)
      expect(form.metrics_count).to eq(2)
    end

    it "returns 0 when no active metrics exist" do
      expect(form.metrics_count).to eq(0)
    end
  end

  context "with empty payload" do
    subject(:form) { described_class.new(draft_payload: {}) }

    it { expect(form.agent_name).to be_nil }
    it { expect(form.experiment_name).to be_nil }
    it { expect(form.prompt).to be_nil }
    it { expect(form.dataset).to be_nil }
  end
end
