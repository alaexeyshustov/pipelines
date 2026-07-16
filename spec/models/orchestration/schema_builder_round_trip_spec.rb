
require "rails_helper"

# Golden-master characterization of the from_schema <-> to_schema bijection and
# the from_params -> to_schema projection. This is the safety net for the
# Serializer/Parser extraction: it must stay byte/structurally identical before
# and after the split.
RSpec.describe Orchestration::SchemaBuilder do
  describe "from_schema -> to_schema round-trip" do
    corpus = {
      "bare string" => { "type" => "string" },
      "string with description" => { "type" => "string", "description" => "A name" },
      "string with format" => { "type" => "string", "format" => "date" },
      "string with enum" => { "type" => "string", "enum" => %w[a b c] },
      "integer with bounds" => { "type" => "integer", "minimum" => 0, "maximum" => 150 },
      "integer with enum" => { "type" => "integer", "enum" => [ 1, 2, 3 ] },
      "integer hardcoded format" => { "type" => "integer", "format" => "hardcoded" },
      "number with float bounds" => { "type" => "number", "minimum" => 0.5, "maximum" => 1.5 },
      "boolean" => { "type" => "boolean" },
      "array of strings" => { "type" => "array", "items" => { "type" => "string" } },
      "array of integers with bounds" => {
        "type" => "array",
        "items" => { "type" => "integer", "minimum" => 1, "maximum" => 9 }
      },
      "object with required and additionalProperties false" => {
        "type" => "object",
        "required" => %w[name],
        "additionalProperties" => false,
        "properties" => {
          "name" => { "type" => "string", "description" => "Full name" },
          "age" => { "type" => "integer", "minimum" => 0, "maximum" => 200 }
        }
      },
      "object with additionalProperties true" => {
        "type" => "object",
        "additionalProperties" => true,
        "properties" => { "id" => { "type" => "string" } }
      },
      "deeply nested object -> object -> array -> object" => {
        "type" => "object",
        "description" => "Root",
        "required" => %w[person],
        "properties" => {
          "person" => {
            "type" => "object",
            "required" => %w[name],
            "properties" => {
              "name" => { "type" => "string" },
              "emails" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "address" => { "type" => "string", "format" => "email" },
                    "primary" => { "type" => "boolean" }
                  }
                }
              }
            }
          },
          "status" => { "type" => "string", "enum" => %w[active inactive] }
        }
      }
    }

    corpus.each do |label, schema|
      it "preserves #{label} (structurally and byte-for-byte)" do
        result = described_class.from_schema(schema).to_schema
        expect(result).to eq(schema)
        expect(result.to_json).to eq(schema.to_json)
      end
    end
  end

  describe "from_params -> to_schema projection" do
    let(:params) do
      {
        "type" => "object",
        "required" => [ "name" ],
        "additionalProperties" => "false",
        "properties" => {
          "name" => { "type" => "string", "description" => "Full name" },
          "age" => { "type" => "integer", "minimum" => "0", "maximum" => "150" },
          "score" => { "type" => "number", "minimum" => "0.5", "maximum" => "1.0" },
          "status" => { "type" => "string", "enum" => %w[active inactive] },
          "tags" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }
    end

    let(:expected_schema) do
      {
        "type" => "object",
        "required" => [ "name" ],
        "additionalProperties" => false,
        "properties" => {
          "name" => { "type" => "string", "description" => "Full name" },
          "age" => { "type" => "integer", "minimum" => 0, "maximum" => 150 },
          "score" => { "type" => "number", "minimum" => 0.5, "maximum" => 1.0 },
          "status" => { "type" => "string", "enum" => %w[active inactive] },
          "tags" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }
    end

    it "coerces params and serializes to the expected schema" do
      expect(described_class.from_params(params).to_schema).to eq(expected_schema)
    end
  end
end
