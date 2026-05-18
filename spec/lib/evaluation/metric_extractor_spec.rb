# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::MetricExtractor do
  describe ".call" do
    it "raises ArgumentError for a blank agent_name" do
      expect { described_class.call("") }.to raise_error(ArgumentError, /blank/)
    end

    it "raises ArgumentError when no prompt exists for the agent" do
      expect { described_class.call("NonExistentAgent") }
        .to raise_error(ArgumentError, /No prompt found/)
    end

    context "with a prompt and a stubbed LLM response" do
      let(:metrics_json) do
        JSON.generate([
          { "name" => "accuracy", "description" => "How accurate the classification is." },
          { "name" => "relevance", "description" => "How relevant the output is." }
        ])
      end

      before do
        create(:orchestration_prompt, name: "Emails::ClassifyAgent", system_prompt: "Classify emails.")
        stub_request(:post, %r{api\.openai\.com})
          .to_return(
            status: 200,
            body: {
              id: "chatcmpl-x", object: "chat.completion", model: "gpt-5.4",
              choices: [ { index: 0, message: { role: "assistant", content: metrics_json }, finish_reason: "stop" } ],
              usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns an array of metric hashes" do
        result = described_class.call("Emails::ClassifyAgent")
        expect(result).to be_an(Array)
        expect(result.first).to include("name" => "accuracy")
      end

      it "returns the correct number of metrics" do
        result = described_class.call("Emails::ClassifyAgent")
        expect(result.size).to eq(2)
      end
    end

    context "when the LLM returns invalid JSON" do
      before do
        create(:orchestration_prompt, name: "Emails::ClassifyAgent")
        stub_request(:post, %r{api\.openai\.com})
          .to_return(
            status: 200,
            body: {
              id: "chatcmpl-x", object: "chat.completion", model: "gpt-5.4",
              choices: [ { index: 0, message: { role: "assistant", content: "not json" }, finish_reason: "stop" } ],
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ArgumentError with a descriptive message" do
        expect { described_class.call("Emails::ClassifyAgent") }
          .to raise_error(ArgumentError, /invalid JSON/)
      end
    end

    context "when the LLM returns a non-array JSON value" do
      before do
        create(:orchestration_prompt, name: "Emails::ClassifyAgent")
        stub_request(:post, %r{api\.openai\.com})
          .to_return(
            status: 200,
            body: {
              id: "chatcmpl-x", object: "chat.completion", model: "gpt-5.4",
              choices: [ { index: 0, message: { role: "assistant", content: '{"not":"array"}' }, finish_reason: "stop" } ],
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ArgumentError" do
        expect { described_class.call("Emails::ClassifyAgent") }
          .to raise_error(ArgumentError, /non-array/)
      end
    end
  end
end
