
require "rails_helper"

RSpec.describe Evaluation::Wizard::Step1Form do
  subject(:form) { described_class.new(draft_payload: payload) }

  let(:payload) do
    {
      "agent_name"       => "Emails::ClassifyAgent",
      "prompt_id"        => "42",
      "experiment_name"  => "My Eval",
      "sample_model"     => "mistral-small",
      "evaluation_model" => "mistral-large"
    }
  end


  describe "#agent_name" do
    it "returns the agent_name from payload" do
      expect(form.agent_name).to eq("Emails::ClassifyAgent")
    end
  end

  describe "#prompt_id" do
    it "returns the prompt_id from payload" do
      expect(form.prompt_id).to eq("42")
    end
  end

  describe "#experiment_name" do
    it "returns the experiment_name from payload" do
      expect(form.experiment_name).to eq("My Eval")
    end
  end

  describe "#sample_model" do
    it "returns the sample_model from payload" do
      expect(form.sample_model).to eq("mistral-small")
    end
  end

  describe "#evaluation_model" do
    it "returns the evaluation_model from payload" do
      expect(form.evaluation_model).to eq("mistral-large")
    end
  end

  describe "#agent_names" do
    it "returns sorted distinct prompt names from the database" do
      create(:orchestration_prompt, name: "Zebra::Agent")
      create(:orchestration_prompt, name: "Alpha::Agent")
      expect(form.agent_names).to eq([ "Alpha::Agent", "Zebra::Agent" ])
    end
  end

  describe "#prompts" do
    it "returns prompts ordered by version descending" do
      p1 = create(:orchestration_prompt, version: 1)
      p2 = create(:orchestration_prompt, version: 3)
      p3 = create(:orchestration_prompt, version: 2)
      expect(form.prompts.to_a).to eq([ p2, p3, p1 ])
    end
  end

  describe "#available_models" do
    it "delegates to Orchestration::Agent.available_models" do
      allow(Orchestration::Agent).to receive(:available_models).and_return(%w[model-a model-b])
      expect(form.available_models).to eq(%w[model-a model-b])
    end
  end

  context "with empty payload" do
    subject(:form) { described_class.new(draft_payload: {}) }

    it { expect(form.agent_name).to be_nil }
    it { expect(form.prompt_id).to be_nil }
    it { expect(form.experiment_name).to be_nil }
    it { expect(form.sample_model).to be_nil }
    it { expect(form.evaluation_model).to be_nil }
  end
end
