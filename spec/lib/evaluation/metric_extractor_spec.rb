require "rails_helper"

RSpec.describe Evaluation::MetricExtractor do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:instructions) { "You are an email classifier. Classify emails by subject." }
  let(:output) do
    { metrics: [
      { name: "classification_accuracy", description: "How accurately emails are classified" },
      { name: "tag_relevance", description: "Whether suggested tags are relevant" }
    ] }
  end
  let(:content) { JSON.generate(output) }

  before do
    create(:orchestration_prompt, name: agent_name, system_prompt: instructions)
    stub_request(:post, %r{api\.openai\.com}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: {
        id: "cmpl-test", object: "chat.completion", model: "gpt-5.4",
        choices: [ { index: 0, message: { role: "assistant", content: content }, finish_reason: "stop" } ],
        usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
      }.to_json
    )
  end

  describe ".call" do
    it "returns name/description hashes parsed from the structured output" do
      expect(described_class.call(agent_name)).to eq(
        [ { "name" => "classification_accuracy", "description" => "How accurately emails are classified" },
          { "name" => "tag_relevance", "description" => "Whether suggested tags are relevant" } ]
      )
    end

    it "does not persist any metrics" do
      expect { described_class.call(agent_name) }.not_to change(Evaluation::Metric, :count)
    end

    it "requests structured output and sends the agent instructions" do
      described_class.call(agent_name)
      expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        body.dig("response_format", "json_schema", "schema", "properties", "metrics") &&
          body["messages"].any? { |m| m["content"].to_s.include?(instructions) }
      })
    end

    it "raises ArgumentError for a blank agent_name" do
      expect { described_class.call("") }.to raise_error(ArgumentError, /agent_name must not be blank/)
    end

    it "raises ArgumentError when no prompt exists for the agent" do
      expect { described_class.call("NonExistentAgent") }.to raise_error(ArgumentError, /No prompt found/)
    end

    context "when the output is not valid JSON" do
      let(:content) { "not json" }

      it "raises ArgumentError" do
        expect { described_class.call(agent_name) }.to raise_error(ArgumentError, /invalid output/)
      end
    end

    context "when the output has no metrics array" do
      let(:content) { JSON.generate({ key: "value" }) }

      it "raises ArgumentError" do
        expect { described_class.call(agent_name) }.to raise_error(ArgumentError, /no metrics/)
      end
    end

    context "when entries are blank" do
      let(:output) { { metrics: [ { name: "ok", description: "fine" }, { name: " ", description: "x" } ] } }

      it "drops them" do
        expect(described_class.call(agent_name).pluck("name")).to eq([ "ok" ])
      end
    end
  end
end
