# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::Step3Form do
  subject(:form) { described_class.new(draft_payload: payload, draft_token: draft_token) }

  let(:payload)     { { "agent_name" => "Emails::ClassifyAgent", "dataset_id" => "7" } }
  let(:draft_token) { "tok_abc123" }


  describe "#agent_name" do
    it "returns the agent_name from payload" do
      expect(form.agent_name).to eq("Emails::ClassifyAgent")
    end
  end

  describe "#selected_dataset_id" do
    it "returns the dataset_id from payload" do
      expect(form.selected_dataset_id).to eq("7")
    end
  end

  describe "#draft_token" do
    it "returns the token passed at initialization" do
      expect(form.draft_token).to eq("tok_abc123")
    end
  end

  describe "#datasets" do
    it "returns datasets ordered by name with record_count" do
      d1 = create(:evaluation_dataset, name: "Zebra Dataset")
      d2 = create(:evaluation_dataset, name: "Alpha Dataset")
      names = form.datasets.map(&:name)
      expect(names).to eq([ d2.name, d1.name ])
    end

    it "includes a record_count attribute" do
      dataset = create(:evaluation_dataset, name: "Test Dataset")
      create(:evaluation_dataset_sample, dataset: dataset)
      result = form.datasets.find { |d| d.id == dataset.id }
      expect(result.record_count.to_i).to eq(1)
    end
  end

  context "with empty payload" do
    subject(:form) { described_class.new(draft_payload: {}, draft_token: nil) }

    it "returns nil for agent_name" do
      expect(form.agent_name).to be_nil
    end

    it "returns nil for selected_dataset_id" do
      expect(form.selected_dataset_id).to be_nil
    end

    it "returns nil for draft_token" do
      expect(form.draft_token).to be_nil
    end
  end
end
