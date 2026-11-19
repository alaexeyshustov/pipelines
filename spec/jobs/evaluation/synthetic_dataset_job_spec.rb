require "rails_helper"

# `:llm` examples run against a local model with LLM_TEST_BACKEND=ollama, which may not answer with a bare JSON
# array; the rest pin the hosted request body or stub specific outputs.
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
    instructions = "You are an email classifier. Classify emails."
    create(:orchestration_prompt, name: agent_name, system_prompt: instructions)

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

      Evaluation::DatasetSample.last(generated_inputs.size).each do |sample|
        expect(sample.expected_tool_calls).to be_nil
      end
    end

    it "updates WizardDraft payload with complete status and dataset_id", :llm do
      described_class.perform_now(**params)

      draft = wizard_draft.reload
      generation = draft.payload["dataset_generation"]
      if LlmTestBackend.live? && generation["status"] == "error"
        expect(generation["error_message"]).to match(/unexpected (character|token)|Expected JSON array/i)
      else
        expect(generation["status"]).to eq("complete")
        expect(generation["dataset_id"]).to eq(Evaluation::Dataset.last.id)
      end
    end

    it "sends agent instructions in the LLM request" do
      described_class.perform_now(**params)

      expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        body["messages"].any? { |m| m["content"].to_s.include?("You are an email classifier. Classify emails.") }
      })
    end

    context "when optional hints are provided" do
      it "includes hints in the LLM user message" do
        described_class.perform_now(**params, hints: "focus on spam")

        expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
          body = JSON.parse(req.body)
          body["messages"].any? { |m| m["content"].to_s.include?("focus on spam") }
        })
      end
    end

    context "when few-shot samples exist" do
      before do
        ds = create(:evaluation_dataset, name: agent_name)
        create(:evaluation_dataset_sample,
               dataset: ds,
               input: { "subject" => "Real email", "body" => "See attached" },
               source_run_id: 1)
      end

      it "still creates the dataset and records" do
        expect {
          described_class.perform_now(**params)
        }.to change(Evaluation::DatasetSample, :count).by(generated_inputs.size)
      end

      it "includes few-shot samples in the LLM user message" do
        described_class.perform_now(**params)

        expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
          body = JSON.parse(req.body)
          body["messages"].any? { |m| m["content"].to_s.include?("few-shot") }
        })
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
        expect(generation["error_message"]).to match(/unexpected (character|token)|Expected JSON array/i)
      end

      it "logs the failure to the job logger" do
        allow(described_class.logger).to receive(:error)

        described_class.perform_now(**params)

        expect(described_class.logger).to have_received(:error).with(/SyntheticDatasetJob.*#{draft_token}/)
      end
    end

    describe "count" do
      def user_message_count
        messages = nil
        WebMock.assert_requested(:post, %r{api\.openai\.com}) { |req| messages = JSON.parse(req.body)["messages"] }
        messages.filter_map { |m| m["content"].to_s[/## Number of examples to generate\n(\S+)/, 1] }.first
      end

      { 0 => "1", -5 => "1", "0" => "1", "-5" => "1", "abc" => "20", "" => "20", nil => "20",
        "10.5" => "20", "010" => "10", "10000" => "50", 10_000 => "50", "7" => "7" }.each do |count, expected|
        it "puts #{expected} in the prompt for count=#{count.inspect}" do
          described_class.perform_now(**params, count: count)

          expect(user_message_count).to eq(expected)
        end
      end
    end

    describe "hints" do
      def hints_in_prompt
        text = nil
        WebMock.assert_requested(:post, %r{api\.openai\.com}) do |req|
          text = JSON.parse(req.body)["messages"].map { |m| m["content"].to_s }.join("\n")
        end
        text[/## Additional hints\n(.*?)(\n\n##|\z)/m, 1]
      end

      it "truncates hints to 1000 characters" do
        described_class.perform_now(**params, hints: "h" * 1500)

        expect(hints_in_prompt.length).to eq(1000)
      end

      it "works with nil hints and omits the hints section" do
        described_class.perform_now(**params, hints: nil)

        expect(hints_in_prompt).to be_nil
        expect(wizard_draft.reload.payload["dataset_generation"]["status"]).to eq("complete")
      end
    end

    context "when the agent is unknown" do
      it "sets the draft to error and creates no dataset" do
        expect {
          described_class.perform_now(**params, agent_name: "Not::AnAgent")
        }.not_to change(Evaluation::Dataset, :count)

        generation = wizard_draft.reload.payload["dataset_generation"]
        expect(generation["status"]).to eq("error")
        expect(generation["error_message"]).to include("Unknown agent")
      end

      it "does not call the LLM" do
        described_class.perform_now(**params, agent_name: "Not::AnAgent")

        expect(WebMock).not_to have_requested(:post, %r{api\.openai\.com})
      end
    end

    context "when the dataset name is too long" do
      it "sets the draft to error and creates no records" do
        expect {
          described_class.perform_now(**params, dataset_name: "n" * 256)
        }.not_to change(Evaluation::DatasetSample, :count)

        expect(wizard_draft.reload.payload["dataset_generation"]["status"]).to eq("error")
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
