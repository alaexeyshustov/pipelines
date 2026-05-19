# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::MetricSuggester do
  subject(:suggester) { described_class.new(agent_name: agent_name) }

  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:instructions) { "You are an email classifier. Classify emails by topic." }

  let(:metrics_json) do
    JSON.generate([
      { "name" => "classification_accuracy", "description" => "How accurately emails are classified", "weight" => 0.5 },
      { "name" => "response_quality",        "description" => "Quality of the response text",         "weight" => 0.3 }
    ])
  end

  let(:llm_response_body) do
    {
      id: "cmpl-test", object: "chat.completion",
      model: "gpt-5.4",
      choices: [ { index: 0, message: { role: "assistant", content: metrics_json }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
    }.to_json
  end

  let(:prompt_double)   { instance_double(Evaluation::Prompt, system_prompt: instructions) }
  let(:prompt_relation) { instance_double(ActiveRecord::Relation) }

  before do
    allow(Evaluation::Prompt).to receive(:where).with(name: agent_name).and_return(prompt_relation)
    allow(prompt_relation).to receive(:order).with(version: :desc, id: :desc).and_return(prompt_relation)
    allow(prompt_relation).to receive(:first).and_return(prompt_double)

    stub_request(:post, %r{api\.openai\.com})
      .to_return(status: 200, body: llm_response_body, headers: { "Content-Type" => "application/json" })
  end

  describe ".call" do
    it "delegates to a new instance" do
      result = described_class.call(agent_name: agent_name)
      expect(result).to be_an(Array).and have_attributes(size: 2)
    end
  end

  describe "#call" do
    it "returns an array of metric hashes" do
      result = suggester.call
      expect(result).to be_an(Array).and have_attributes(size: 2)
    end

    it "returns hashes with symbol keys name, description, weight" do
      result = suggester.call
      expect(result.first).to include(
        name: "classification_accuracy",
        description: a_kind_of(String),
        weight: be_a(Float)
      )
    end

    it "sends the agent system prompt to the LLM" do
      suggester.call
      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        body["messages"].any? { |m| m["content"].to_s.include?(instructions) }
      }
    end

    it "does not persist any metrics" do
      expect { suggester.call }.not_to change(Evaluation::Metric, :count)
    end

    context "when agent prompt is not found" do
      before { allow(prompt_relation).to receive(:first).and_return(nil) }

      it "raises MetricSuggester::Error" do
        expect { suggester.call }.to raise_error(Evaluation::MetricSuggester::Error, /No prompt found/)
      end
    end

    context "when LLM returns invalid JSON" do
      let(:llm_response_body) do
        {
          id: "cmpl-test", object: "chat.completion",
          model: "gpt-5.4",
          choices: [ { index: 0, message: { role: "assistant", content: "not json at all" }, finish_reason: "stop" } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it "raises MetricSuggester::Error" do
        expect { suggester.call }.to raise_error(Evaluation::MetricSuggester::Error)
      end
    end

    context "when LLM returns a non-array JSON value" do
      let(:llm_response_body) do
        {
          id: "cmpl-test", object: "chat.completion",
          model: "gpt-5.4",
          choices: [ { index: 0, message: { role: "assistant", content: '{"key":"value"}' }, finish_reason: "stop" } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json
      end

      it "raises MetricSuggester::Error" do
        expect { suggester.call }.to raise_error(Evaluation::MetricSuggester::Error, /Expected JSON array/)
      end
    end

    context "when an entry has an out-of-range weight" do
      let(:metrics_json) do
        JSON.generate([
          { "name" => "good_metric", "description" => "Valid",   "weight" => 0.5 },
          { "name" => "bad_weight",  "description" => "Invalid", "weight" => 1.5 }
        ])
      end

      it "drops the invalid entry and returns the rest" do
        result = suggester.call
        expect(result.map { _1[:name] }).to eq([ "good_metric" ])
      end
    end

    context "when an entry has a blank name" do
      let(:metrics_json) do
        JSON.generate([
          { "name" => "",            "description" => "No name", "weight" => 0.4 },
          { "name" => "valid_name",  "description" => "Has name", "weight" => 0.6 }
        ])
      end

      it "drops the blank-name entry" do
        result = suggester.call
        expect(result.map { _1[:name] }).to eq([ "valid_name" ])
      end
    end

    context "when an entry has an unparseable weight" do
      let(:metrics_json) do
        JSON.generate([
          { "name" => "ok",  "description" => "Fine",       "weight" => 0.5 },
          { "name" => "bad", "description" => "Bad weight", "weight" => "not-a-float" }
        ])
      end

      it "drops the unparseable entry" do
        result = suggester.call
        expect(result.map { _1[:name] }).to eq([ "ok" ])
      end
    end
  end
end
