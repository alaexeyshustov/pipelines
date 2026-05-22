# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::SyntheticDatasetJob do
  let(:draft_token)   { "tok_xyz789" }
  let(:agent_name)    { "Emails::ClassifyAgent" }
  let!(:wizard_draft) { create(:evaluation_wizard_draft, session_token: draft_token) }

  let(:generated_inputs) do
    [
      { "subject" => "Hello", "body" => "Hi there" },
      { "subject" => "Invoice", "body" => "Please find attached" },
      { "subject" => "Meeting", "body" => "Let's meet tomorrow" }
    ]
  end

  let(:llm_response_body) do
    {
      id: "cmpl-test", object: "chat.completion",
      model: "gpt-5.4",
      choices: [ { index: 0, message: { role: "assistant", content: JSON.generate(generated_inputs) }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 150, completion_tokens: 80, total_tokens: 230 }
    }.to_json
  end

  let(:params) { { draft_token: draft_token, agent_name: agent_name, dataset_name: "Synthetic emails v1", count: 3 } }

  before do
    instructions  = "You are an email classifier. Classify emails."
    prompt_rel    = instance_double(ActiveRecord::Relation)
    prompt_double = instance_double(Evaluation::Prompt, system_prompt: instructions)

    allow(Evaluation::Prompt).to receive(:where).with(name: agent_name).and_return(prompt_rel)
    allow(prompt_rel).to receive(:order).with(version: :desc, id: :desc).and_return(prompt_rel)
    allow(prompt_rel).to receive(:first).and_return(prompt_double)

    allow(Evaluation::Dataset).to receive(:where).with(name: agent_name).and_return(
      instance_double(ActiveRecord::Relation, first: nil)
    )

    stub_request(:post, %r{api\.openai\.com})
      .to_return(status: 200, body: llm_response_body, headers: { "Content-Type" => "application/json" })
  end

  describe "#perform" do
    it "creates a Evaluation::Dataset with the given name" do
      expect { described_class.perform_now(**params) }.to change(Evaluation::Dataset, :count).by(1)

      expect(Evaluation::Dataset.last.name).to eq("Synthetic emails v1")
    end

    it "creates one DatasetSample per generated input" do
      expect {
        described_class.perform_now(**params)
      }.to change(Evaluation::DatasetSample, :count).by(generated_inputs.size)
    end

    it "associates each DatasetSample with the dataset" do
      described_class.perform_now(**params)

      dataset = Evaluation::Dataset.last
      expect(dataset.dataset_samples.count).to eq(generated_inputs.size)
    end

    it "stores generated inputs in DatasetSample" do
      described_class.perform_now(**params)

      first_sample = Evaluation::DatasetSample.last(generated_inputs.size).first
      expect(first_sample.input).to eq(generated_inputs.first)
    end

    it "leaves expected_tool_calls nil on created DatasetSamples" do
      described_class.perform_now(**params)

      expect(Evaluation::DatasetSample.last(generated_inputs.size).map(&:expected_tool_calls)).to all(be_nil)
    end

    it "updates WizardDraft payload with complete status and dataset_id" do
      described_class.perform_now(**params)

      draft = wizard_draft.reload
      generation = draft.payload["dataset_generation"]
      expect(generation["status"]).to eq("complete")
      expect(generation["dataset_id"]).to eq(Evaluation::Dataset.last.id)
    end

    it "sends agent instructions in the LLM request" do
      described_class.perform_now(**params)

      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        body["messages"].any? { |m| m["content"].to_s.include?("You are an email classifier. Classify emails.") }
      }
    end

    context "when optional hints are provided" do
      it "includes hints in the LLM user message" do
        described_class.perform_now(**params, hints: "focus on spam")

        expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
          body = JSON.parse(req.body)
          body["messages"].any? { |m| m["content"].to_s.include?("focus on spam") }
        }
      end
    end

    context "when few-shot samples exist" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        ds = create(:evaluation_dataset, name: agent_name)
        create(:evaluation_dataset_sample,
               dataset: ds,
               input: { "subject" => "Real email", "body" => "See attached" },
               source_run_id: 1)
        allow(Evaluation::Dataset).to receive(:where).with(name: agent_name).and_call_original
      end

      it "still creates the dataset and records" do
        expect {
          described_class.perform_now(**params)
        }.to change(Evaluation::DatasetSample, :count).by(generated_inputs.size)
      end

      it "includes few-shot samples in the LLM user message" do
        described_class.perform_now(**params)

        expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
          body = JSON.parse(req.body)
          body["messages"].any? { |m| m["content"].to_s.include?("few-shot") }
        }
      end
    end

    context "when LLM returns invalid JSON" do
      let(:llm_response_body) do
        {
          id: "cmpl-test", object: "chat.completion",
          model: "gpt-5.4",
          choices: [ { index: 0, message: { role: "assistant", content: "not json" }, finish_reason: "stop" } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it "does not create any records" do
        expect {
          described_class.perform_now(**params)
        }.not_to change(Evaluation::DatasetSample, :count)
      end

      it "updates WizardDraft payload with error status" do
        described_class.perform_now(**params)

        generation = wizard_draft.reload.payload["dataset_generation"]
        expect(generation["status"]).to eq("error")
        expect(generation["error_message"]).to be_present
      end

      it "logs the failure to the job logger" do
        allow(described_class.logger).to receive(:error)

        described_class.perform_now(**params)

        expect(described_class.logger).to have_received(:error).with(/SyntheticDatasetJob.*#{draft_token}/)
      end
    end

    context "when LLM returns a non-array JSON value" do
      let(:llm_response_body) do
        {
          id: "cmpl-test", object: "chat.completion",
          model: "gpt-5.4",
          choices: [ { index: 0, message: { role: "assistant", content: '{"not":"array"}' }, finish_reason: "stop" } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it "updates WizardDraft payload with error status" do
        described_class.perform_now(**params)

        generation = wizard_draft.reload.payload["dataset_generation"]
        expect(generation["status"]).to eq("error")
      end
    end
  end
end
