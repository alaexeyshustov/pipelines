require "rails_helper"

RSpec.describe Orchestration::ModelOutputParser do
  subject(:parser) { described_class.new }

  let(:policy) do
    Orchestration::AgentResolutionPolicy::Result.new(
      model: "gpt-4.1-mini", prompt: "system prompt", tools: nil,
      output_schema: { "type" => "object", "required" => [ "result" ], "properties" => { "result" => { "type" => "array" } } }
    )
  end

  describe "#parse" do
    it "returns a Hash content unchanged with stringified keys" do
      result = parser.parse({ result: [ 1 ] }, structured_output_expected: true)
      expect(result).to eq("result" => [ 1 ])
    end

    it "parses a JSON string content into a Hash with stringified keys" do
      result = parser.parse('{"result":[1,2]}', structured_output_expected: true)
      expect(result).to eq("result" => [ 1, 2 ])
    end

    it "raises InvalidModelOutputError for a non-JSON string when structured output is expected" do
      expect { parser.parse("plain text", structured_output_expected: true) }
        .to raise_error(Orchestration::InvalidModelOutputError, /Invalid model output/)
    end

    it "returns nil for a non-JSON string when structured output is not expected" do
      expect(parser.parse("plain text", structured_output_expected: false)).to be_nil
    end

    it "raises InvalidModelOutputError for a JSON array when structured output is expected" do
      expect { parser.parse("[1,2,3]", structured_output_expected: true) }
        .to raise_error(Orchestration::InvalidModelOutputError, /expected JSON object/)
    end

    it "returns nil for non-Hash, non-String content when structured output is not expected" do
      expect(parser.parse(nil, structured_output_expected: false)).to be_nil
    end

    it "preserves the raw content on the raised error" do
      parser.parse("not json", structured_output_expected: true)
    rescue Orchestration::InvalidModelOutputError => e
      expect(e.raw_content).to eq("not json")
    end
  end

  describe "#validate!" do
    it "passes for output matching the schema" do
      expect { parser.validate!({ "result" => [ 1 ] }, policy: policy, raw_content: nil) }.not_to raise_error
    end

    it "raises InvalidModelOutputError with the raw_content when output fails schema validation" do
      expect { parser.validate!({ "result" => "not an array" }, policy: policy, raw_content: "raw") }
        .to raise_error(Orchestration::InvalidModelOutputError) { |e| expect(e.raw_content).to eq("raw") }
    end

    it "does not raise when the policy has no output_schema" do
      blank_policy = Orchestration::AgentResolutionPolicy::Result.new(
        model: "gpt-4.1-mini", prompt: "p", tools: nil, output_schema: nil
      )

      expect { parser.validate!({ "anything" => true }, policy: blank_policy, raw_content: nil) }.not_to raise_error
    end
  end
end
