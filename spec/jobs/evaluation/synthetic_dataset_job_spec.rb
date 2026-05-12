# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::SyntheticDatasetJob do
  let(:draft_token)   { "tok_xyz789" }
  let(:agent_name)    { "Emails::ClassifyAgent" }
  let(:dataset_name)  { "Synthetic emails v1" }
  let(:count)         { 3 }

  let(:instructions)  { "You are an email classifier. Classify emails." }
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
      id: "msg_01", type: "message", role: "assistant",
      content: [ { type: "text", text: JSON.generate(generated_inputs) } ],
      model: "claude-sonnet-4-6", stop_reason: "end_turn",
      usage: { input_tokens: 150, output_tokens: 80 }
    }.to_json
  end

  let(:prompt_double)   { instance_double(Orchestration::Prompt, system_prompt: instructions) }
  let(:prompt_relation) { instance_double(ActiveRecord::Relation) }

  before do
    allow(Orchestration::Prompt).to receive(:where).with(name: agent_name).and_return(prompt_relation)
    allow(prompt_relation).to receive(:order).with(version: :desc, id: :desc).and_return(prompt_relation)
    allow(prompt_relation).to receive(:first).and_return(prompt_double)

    allow(Leva::Dataset).to receive(:where).with(name: agent_name).and_return(
      instance_double(ActiveRecord::Relation, first: nil)
    )

    stub_request(:post, %r{api\.anthropic\.com})
      .to_return(status: 200, body: llm_response_body, headers: { "Content-Type" => "application/json" })
  end

  describe "#perform" do
    it "creates a Leva::Dataset with the given name" do
      expect {
        described_class.perform_now(
          draft_token: draft_token, agent_name: agent_name,
          dataset_name: dataset_name, count: count
        )
      }.to change(Leva::Dataset, :count).by(1)

      expect(Leva::Dataset.last.name).to eq(dataset_name)
    end

    it "creates one SyntheticRecord per generated input" do
      expect {
        described_class.perform_now(
          draft_token: draft_token, agent_name: agent_name,
          dataset_name: dataset_name, count: count
        )
      }.to change(Evaluation::SyntheticRecord, :count).by(generated_inputs.size)
    end

    it "associates each SyntheticRecord with the dataset via DatasetRecord" do
      described_class.perform_now(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: count
      )

      dataset = Leva::Dataset.last
      expect(dataset.dataset_records.count).to eq(generated_inputs.size)
      expect(dataset.dataset_records.first.recordable).to be_a(Evaluation::SyntheticRecord)
    end

    it "updates WizardDraft payload with complete status and dataset_id" do
      described_class.perform_now(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: count
      )

      draft = wizard_draft.reload
      generation = draft.payload["dataset_generation"]
      expect(generation["status"]).to eq("complete")
      expect(generation["dataset_id"]).to eq(Leva::Dataset.last.id)
    end

    it "sends agent instructions in the LLM request" do
      described_class.perform_now(
        draft_token: draft_token, agent_name: agent_name,
        dataset_name: dataset_name, count: count
      )

      expect(WebMock).to have_requested(:post, %r{api\.anthropic\.com}).with { |req|
        body = JSON.parse(req.body)
        body["messages"].any? { |m| m["content"].to_s.include?(instructions) }
      }
    end

    context "when optional hints are provided" do
      it "includes hints in the LLM user message" do
        described_class.perform_now(
          draft_token: draft_token, agent_name: agent_name,
          dataset_name: dataset_name, count: count, hints: "focus on spam"
        )

        expect(WebMock).to have_requested(:post, %r{api\.anthropic\.com}).with { |req|
          body = JSON.parse(req.body)
          body["messages"].any? { |m| m["content"].to_s.include?("focus on spam") }
        }
      end
    end

    context "when few-shot samples exist" do
      before do
        allow_any_instance_of(described_class).to receive(:fetch_few_shot_samples)
          .and_return([ { "subject" => "Real email", "body" => "See attached" } ])
      end

      it "still creates the dataset and records" do
        expect {
          described_class.perform_now(
            draft_token: draft_token, agent_name: agent_name,
            dataset_name: dataset_name, count: count
          )
        }.to change(Evaluation::SyntheticRecord, :count).by(generated_inputs.size)
      end

      it "includes few-shot samples in the LLM user message" do
        described_class.perform_now(
          draft_token: draft_token, agent_name: agent_name,
          dataset_name: dataset_name, count: count
        )

        expect(WebMock).to have_requested(:post, %r{api\.anthropic\.com}).with { |req|
          body = JSON.parse(req.body)
          body["messages"].any? { |m| m["content"].to_s.include?("few-shot") }
        }
      end
    end

    context "when LLM returns invalid JSON" do
      let(:llm_response_body) do
        {
          id: "msg_err", type: "message", role: "assistant",
          content: [ { type: "text", text: "not json" } ],
          model: "claude-sonnet-4-6", stop_reason: "end_turn",
          usage: { input_tokens: 10, output_tokens: 5 }
        }.to_json
      end

      it "does not create any records" do
        expect {
          described_class.perform_now(
            draft_token: draft_token, agent_name: agent_name,
            dataset_name: dataset_name, count: count
          )
        }.not_to change(Evaluation::SyntheticRecord, :count)
      end

      it "updates WizardDraft payload with error status" do
        described_class.perform_now(
          draft_token: draft_token, agent_name: agent_name,
          dataset_name: dataset_name, count: count
        )

        generation = wizard_draft.reload.payload["dataset_generation"]
        expect(generation["status"]).to eq("error")
        expect(generation["error_message"]).to be_present
      end
    end

    context "when LLM returns a non-array JSON value" do
      let(:llm_response_body) do
        {
          id: "msg_err2", type: "message", role: "assistant",
          content: [ { type: "text", text: '{"not":"array"}' } ],
          model: "claude-sonnet-4-6", stop_reason: "end_turn",
          usage: { input_tokens: 10, output_tokens: 5 }
        }.to_json
      end

      it "updates WizardDraft payload with error status" do
        described_class.perform_now(
          draft_token: draft_token, agent_name: agent_name,
          dataset_name: dataset_name, count: count
        )

        generation = wizard_draft.reload.payload["dataset_generation"]
        expect(generation["status"]).to eq("error")
      end
    end
  end
end
