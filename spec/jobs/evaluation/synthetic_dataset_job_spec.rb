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
    prompt_double = instance_double(Orchestration::Prompt, system_prompt: instructions)

    allow(Orchestration::Prompt).to receive(:where).with(name: agent_name).and_return(prompt_rel)
    allow(prompt_rel).to receive(:order).with(version: :desc, id: :desc).and_return(prompt_rel)
    allow(prompt_rel).to receive(:first).and_return(prompt_double)

    allow(Leva::Dataset).to receive(:where).with(name: agent_name).and_return(
      instance_double(ActiveRecord::Relation, first: nil)
    )

    stub_request(:post, %r{api\.openai\.com})
      .to_return(status: 200, body: llm_response_body, headers: { "Content-Type" => "application/json" })
  end

  describe "#perform" do
    it "creates a Leva::Dataset with the given name" do
      expect { described_class.perform_now(**params) }.to change(Leva::Dataset, :count).by(1)

      expect(Leva::Dataset.last.name).to eq("Synthetic emails v1")
    end

    it "creates one SyntheticRecord per generated input" do
      expect {
        described_class.perform_now(**params)
      }.to change(Evaluation::SyntheticRecord, :count).by(generated_inputs.size)
    end

    it "associates each SyntheticRecord with the dataset via DatasetRecord" do
      described_class.perform_now(**params)

      dataset = Leva::Dataset.last
      expect(dataset.dataset_records.count).to eq(generated_inputs.size)
      expect(dataset.dataset_records.first.recordable).to be_a(Evaluation::SyntheticRecord)
    end

    it "updates WizardDraft payload with complete status and dataset_id" do
      described_class.perform_now(**params)

      draft = wizard_draft.reload
      generation = draft.payload["dataset_generation"]
      expect(generation["status"]).to eq("complete")
      expect(generation["dataset_id"]).to eq(Leva::Dataset.last.id)
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

    context "when few-shot samples exist" do
      before do
        records_double = instance_double(ActiveRecord::Relation)
        dataset_double = instance_double(Leva::Dataset)

        allow(Leva::Dataset).to receive(:where).with(name: agent_name).and_return(
          instance_double(ActiveRecord::Relation, first: dataset_double)
        )
        allow(dataset_double).to receive(:dataset_records).and_return(records_double)
        allow(records_double).to receive_messages(joins: records_double, limit: records_double, pluck: [ { "subject" => "Real email", "body" => "See attached" }.to_json ])
      end

      it "still creates the dataset and records" do
        expect {
          described_class.perform_now(**params)
        }.to change(Evaluation::SyntheticRecord, :count).by(generated_inputs.size)
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
        }.not_to change(Evaluation::SyntheticRecord, :count)
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
