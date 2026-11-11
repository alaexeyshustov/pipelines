require "rails_helper"

RSpec.describe Evaluation::MetricSuggester do
  subject(:suggester) { described_class.new(agent_name: agent_name) }

  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:instructions) { "You are an email classifier. Classify emails by topic." }
  let(:entries) do
    [
      { name: "is_correct", description: "Is the label right", weight: 0.5, kind: "probability",
        levels: [], options: [], minimum: 0.8 },
      { name: "quality", description: "Quality of the reply", weight: 0.3, kind: "score",
        levels: [ "wrong", "ok", "great" ], options: [], minimum: 0.5 },
      { name: "tone", description: "Tone of the reply", weight: 0.2, kind: "choice", levels: [], minimum: 0.5,
        options: [ { name: "formal", description: "Formal tone", value: 1.0 },
                   { name: "rude", description: "Rude tone", value: 0.0 } ] }
    ]
  end
  let(:content) { JSON.generate({ metrics: entries }) }

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
    it "delegates to a new instance" do
      expect(described_class.call(agent_name: agent_name).size).to eq(3)
    end
  end

  describe "#call" do
    it "maps entries to Metric columns: kind, levels, weight, minimum" do
      expect(suggester.call).to eq(
        [
          { name: "is_correct", description: "Is the label right", weight: 0.5, kind: "probability", levels: nil, minimum: 0.8 },
          { name: "quality", description: "Quality of the reply", weight: 0.3, kind: "score", levels: [ "wrong", "ok", "great" ], minimum: 0.5 },
          { name: "tone", description: "Tone of the reply", weight: 0.2, kind: "choice", minimum: 0.5,
            levels: { "formal" => { "description" => "Formal tone", "value" => 1.0 },
                      "rude" => { "description" => "Rude tone", "value" => 0.0 } } }
        ]
      )
    end

    it "yields attributes that build valid Metric rows" do
      suggester.call.each do |attrs|
        expect(Evaluation::Metric.new(attrs.merge(agent_name: agent_name))).to be_valid
      end
    end

    it "requests structured output with the metric schema and sends the agent prompt" do
      suggester.call
      expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
        body = JSON.parse(req.body)
        item = body.dig("response_format", "json_schema", "schema", "properties", "metrics", "items", "properties")
        item.key?("levels") && item.key?("options") && item.dig("kind", "enum") == %w[probability score choice] &&
          body["messages"].any? { |m| m["content"].to_s.include?(instructions) }
      })
    end

    it "does not persist any metrics" do
      expect { suggester.call }.not_to change(Evaluation::Metric, :count)
    end

    it "raises Error when no prompt exists" do
      expect { described_class.call(agent_name: "NonExistentAgent") }
        .to raise_error(described_class::Error, /No prompt found/)
    end

    context "when the output is not valid JSON" do
      let(:content) { "not json at all" }

      it("raises Error") { expect { suggester.call }.to raise_error(described_class::Error) }
    end

    context "when the output has no metrics array" do
      let(:content) { JSON.generate({ key: "value" }) }

      it("raises Error") { expect { suggester.call }.to raise_error(described_class::Error, /metrics array/) }
    end

    context "when a score has fewer than two levels or a choice fewer than two options" do
      let(:entries) do
        [ { name: "a", description: "A", weight: 0.5, kind: "score", levels: [ "only" ], options: [], minimum: 0.5 },
          { name: "b", description: "B", weight: 0.5, kind: "choice", levels: [], minimum: 0.5,
            options: [ { name: "x", description: "X", value: 1.0 } ] } ]
      end

      it "degrades them to probability metrics" do
        expect(suggester.call).to all(include(kind: "probability", levels: nil))
      end
    end

    context "when entries are invalid" do
      let(:entries) do
        [ { name: "good", description: "Valid", weight: 0.5, kind: "probability", levels: [], options: [], minimum: 2 },
          { name: "bad_weight", description: "Invalid", weight: 1.5, kind: "probability", levels: [], options: [], minimum: 0.5 },
          { name: "", description: "No name", weight: 0.4, kind: "probability", levels: [], options: [], minimum: 0.5 },
          { name: "nan", description: "Bad weight", weight: "not-a-float", kind: "probability", levels: [], options: [], minimum: 0.5 } ]
      end

      it "drops them and clamps the minimum" do
        expect(suggester.call).to match([ include(name: "good", minimum: 1.0) ])
      end
    end
  end
end
