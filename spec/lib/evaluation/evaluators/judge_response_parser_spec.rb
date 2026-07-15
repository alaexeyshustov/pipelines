require "rails_helper"

RSpec.describe Evaluation::Evaluators::JudgeResponseParser do
  subject(:parser) { described_class.new }

  describe "#parse_output" do
    it "returns an empty string for blank output" do
      expect(parser.parse_output(nil)).to eq("")
      expect(parser.parse_output("")).to eq("")
    end

    it "parses JSON output into structured data" do
      expect(parser.parse_output('{"id":"abc123"}')).to eq({ "id" => "abc123" })
    end

    it "returns the raw string when it is not valid JSON" do
      expect(parser.parse_output("plain text")).to eq("plain text")
    end
  end

  describe "#parse" do
    it "normalizes a hash with an evaluations array" do
      content = { "evaluations" => [
        { "metric_name" => "accuracy", "score" => 4, "justification" => "Good." }
      ] }

      expect(parser.parse(content)).to eq([
        { metric_name: "accuracy", score: 4.0, justification: "Good." }
      ])
    end

    it "normalizes a raw array of entries" do
      content = [ { "metric_name" => "accuracy", "score" => "5", "justification" => "Great." } ]

      expect(parser.parse(content)).to eq([
        { metric_name: "accuracy", score: 5.0, justification: "Great." }
      ])
    end

    it "parses a JSON string payload" do
      content = [ { "metric_name" => "accuracy", "score" => 3, "justification" => "OK." } ].to_json

      expect(parser.parse(content)).to eq([
        { metric_name: "accuracy", score: 3.0, justification: "OK." }
      ])
    end

    it "drops entries with a score outside 1..5" do
      content = [ { "metric_name" => "accuracy", "score" => 10, "justification" => "Way off." } ]

      expect(parser.parse(content)).to eq([])
    end

    it "drops entries missing metric_name or justification" do
      content = [ { "metric_name" => "", "score" => 4, "justification" => "" } ]

      expect(parser.parse(content)).to eq([])
    end

    it "drops entries with an unparseable score" do
      content = [ { "metric_name" => "accuracy", "score" => "not-a-number", "justification" => "Bad." } ]

      expect(parser.parse(content)).to eq([])
    end

    it "ignores entries missing a score" do
      content = [ { "metric_name" => "accuracy", "justification" => "No score." } ]

      expect(parser.parse(content)).to eq([])
    end

    it "returns an empty array for content that is not a hash or array" do
      expect(parser.parse("not a hash")).to eq([])
    end

    it "returns an empty array when parsing raises JSON::ParserError" do
      expect(parser.parse("not json {")).to eq([])
    end
  end

  describe ".parse_output and .parse" do
    it "delegates the class method to a new instance" do
      expect(described_class.parse_output(nil)).to eq("")
      expect(described_class.parse([ { "metric_name" => "a", "score" => 4, "justification" => "j" } ]))
        .to eq([ { metric_name: "a", score: 4.0, justification: "j" } ])
    end
  end
end
