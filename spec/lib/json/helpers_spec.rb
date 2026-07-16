
require "rails_helper"

RSpec.describe JSON::Helpers do
  describe ".parse_maybe" do
    it "parses a JSON string" do
      expect(described_class.parse_maybe('{"a":1}')).to eq({ "a" => 1 })
    end

    it "returns a Hash unchanged" do
      hash = { "a" => 1 }
      expect(described_class.parse_maybe(hash)).to equal(hash)
    end

    it "returns an Array unchanged" do
      array = [ 1, 2, 3 ]
      expect(described_class.parse_maybe(array)).to equal(array)
    end

    it "returns nil unchanged" do
      expect(described_class.parse_maybe(nil)).to be_nil
    end

    it "raises JSON::ParserError for malformed JSON strings (fail-loud, no rescue)" do
      expect { described_class.parse_maybe("not json") }.to raise_error(JSON::ParserError)
    end

    it "returns a non-String, non-Array, non-Hash value unchanged" do
      expect(described_class.parse_maybe(42)).to eq(42)
    end
  end

  describe ".safe_parse" do
    it "parses a JSON string" do
      expect(described_class.safe_parse('{"a":1}')).to eq({ "a" => 1 })
    end

    it "returns fallback for non-String input" do
      expect(described_class.safe_parse(nil, fallback: {})).to eq({})
    end

    it "returns fallback for malformed JSON" do
      expect(described_class.safe_parse("not json", fallback: {})).to eq({})
    end
  end

  describe ".safe_generate" do
    it "returns a String unchanged" do
      expect(described_class.safe_generate("already a string")).to eq("already a string")
    end

    it "generates JSON for a Hash" do
      expect(described_class.safe_generate({ "a" => 1 })).to eq('{"a":1}')
    end
  end
end
