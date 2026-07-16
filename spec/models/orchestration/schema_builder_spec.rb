
require "rails_helper"

RSpec.describe Orchestration::SchemaBuilder do
  # --- from_schema ---

  describe ".from_schema" do
    let(:nested_object_schema) do
      {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "age" => { "type" => "integer", "minimum" => 0, "maximum" => 150 }
        }
      }
    end

    it "returns an empty builder for nil" do
      builder = described_class.from_schema(nil)
      expect(builder.type).to be_nil
      expect(builder.properties).to eq({})
    end

    it "returns an empty builder for blank hash" do
      builder = described_class.from_schema({})
      expect(builder.type).to be_nil
    end

    it "parses type and description" do
      builder = described_class.from_schema("type" => "string", "description" => "A name")
      expect(builder.type).to eq("string")
      expect(builder.description).to eq("A name")
    end

    it "parses format for string type" do
      builder = described_class.from_schema("type" => "string", "format" => "date")
      expect(builder.format).to eq("date")
    end

    it "parses required array" do
      builder = described_class.from_schema("type" => "object", "required" => %w[name age])
      expect(builder.required).to eq(%w[name age])
    end

    it "parses boolean additionalProperties" do
      builder = described_class.from_schema("type" => "object", "additionalProperties" => false)
      expect(builder.additional_properties).to be false
    end

    it "parses properties as nested SchemaBuilders" do # rubocop:disable RSpec/MultipleExpectations
      builder = described_class.from_schema(nested_object_schema)
      expect(builder.properties["name"]).to be_a(described_class)
      expect(builder.properties["name"].type).to eq("string")
      expect(builder.properties["age"].minimum).to eq(0)
      expect(builder.properties["age"].maximum).to eq(150)
    end

    it "parses array items as a nested SchemaBuilder" do
      schema = { "type" => "array", "items" => { "type" => "string" } }
      builder = described_class.from_schema(schema)
      expect(builder.items).to be_a(described_class)
      expect(builder.items.type).to eq("string")
    end

    it "parses enum" do
      schema = { "type" => "string", "enum" => %w[a b c] }
      builder = described_class.from_schema(schema)
      expect(builder.enum).to eq(%w[a b c])
    end
  end

  # --- to_schema ---

  describe "#to_schema" do
    it "outputs empty hash for blank builder" do
      expect(described_class.new.to_schema).to eq({})
    end

    it "includes type and description" do
      builder = described_class.new(type: "string", description: "A name")
      expect(builder.to_schema).to eq("type" => "string", "description" => "A name")
    end

    it "includes format for string type when present" do
      builder = described_class.new(type: "string", format: "date")
      expect(builder.to_schema).to eq("type" => "string", "format" => "date")
    end

    it "does not include format for non-string types" do
      builder = described_class.new(type: "integer", format: "date")
      expect(builder.to_schema).not_to have_key("format")
    end

    it "includes format 'hardcoded' regardless of type" do
      builder = described_class.new(type: "integer", format: "hardcoded")
      expect(builder.to_schema).to include("format" => "hardcoded")
    end

    it "omits description when blank" do
      builder = described_class.new(type: "string")
      expect(builder.to_schema).not_to have_key("description")
    end

    it "includes required and additionalProperties for object type" do
      builder = described_class.new(
        type: "object",
        required: [ "name" ],
        additional_properties: false
      )
      schema = builder.to_schema
      expect(schema["required"]).to eq([ "name" ])
      expect(schema["additionalProperties"]).to be false
    end

    it "includes properties for object type" do
      name_b = described_class.new(type: "string")
      builder = described_class.new(type: "object", properties: { "name" => name_b })
      expect(builder.to_schema["properties"]).to eq("name" => { "type" => "string" })
    end

    it "includes items for array type" do
      items_b = described_class.new(type: "string")
      builder = described_class.new(type: "array", items: items_b)
      expect(builder.to_schema["items"]).to eq("type" => "string")
    end

    it "includes enum for string type" do
      builder = described_class.new(type: "string", enum: %w[a b])
      expect(builder.to_schema["enum"]).to eq(%w[a b])
    end

    it "includes minimum and maximum for numeric types" do
      builder = described_class.new(type: "integer", minimum: 0, maximum: 100)
      expect(builder.to_schema).to include("minimum" => 0, "maximum" => 100)
    end

    it "does not include object-only fields for non-object types" do
      builder = described_class.new(type: "string", required: [ "x" ])
      expect(builder.to_schema).not_to have_key("required")
    end

    it "does not include numeric fields for non-numeric types" do
      builder = described_class.new(type: "string", minimum: 0)
      expect(builder.to_schema).not_to have_key("minimum")
    end
  end

  # --- round-trip ---

  describe "from_schema → to_schema round-trip" do
    let(:schema) do
      {
        "type" => "object",
        "description" => "Person",
        "required" => [ "name" ],
        "additionalProperties" => false,
        "properties" => {
          "name" => { "type" => "string", "description" => "Full name" },
          "age" => { "type" => "integer", "minimum" => 0, "maximum" => 200 },
          "tags" => { "type" => "array", "items" => { "type" => "string" } },
          "status" => { "type" => "string", "enum" => %w[active inactive] }
        }
      }
    end

    it "preserves all fields" do
      expect(described_class.from_schema(schema).to_schema).to eq(schema)
    end

    it "preserves format on string properties" do
      schema_with_format = schema.merge(
        "properties" => schema["properties"].merge(
          "due_date" => { "type" => "string", "format" => "date" }
        )
      )
      expect(described_class.from_schema(schema_with_format).to_schema).to eq(schema_with_format)
    end
  end

  # --- from_params ---

  describe ".from_params" do
    it "parses string type" do
      builder = described_class.from_params("type" => "string", "description" => "Name")
      expect(builder.type).to eq("string")
      expect(builder.description).to eq("Name")
    end

    it "parses format" do
      builder = described_class.from_params("type" => "string", "format" => "date")
      expect(builder.format).to eq("date")
    end

    it "coerces additionalProperties string to boolean" do
      expect(described_class.from_params("type" => "object", "additionalProperties" => "false").additional_properties).to be false
      expect(described_class.from_params("type" => "object", "additionalProperties" => "true").additional_properties).to be true
    end

    it "coerces minimum/maximum to integer for integer type" do
      builder = described_class.from_params("type" => "integer", "minimum" => "18", "maximum" => "150")
      expect(builder.minimum).to eq(18)
      expect(builder.maximum).to eq(150)
    end

    it "coerces minimum/maximum to float for number type" do
      builder = described_class.from_params("type" => "number", "minimum" => "0.5", "maximum" => "1.0")
      expect(builder.minimum).to eq(0.5)
      expect(builder.maximum).to eq(1.0)
    end

    it "ignores blank minimum/maximum" do
      builder = described_class.from_params("type" => "integer", "minimum" => "", "maximum" => "")
      expect(builder.minimum).to be_nil
      expect(builder.maximum).to be_nil
    end

    it "parses nested properties" do
      params = {
        "type" => "object",
        "properties" => { "name" => { "type" => "string" } }
      }
      builder = described_class.from_params(params)
      expect(builder.properties["name"].type).to eq("string")
    end

    it "parses enum array" do
      builder = described_class.from_params("type" => "string", "enum" => %w[a b])
      expect(builder.enum).to eq(%w[a b])
    end
  end

  # --- mutations ---

  describe "#add_property" do
    it "adds a new string property" do
      builder = described_class.new(type: "object")
      new_b = builder.add_property("email")
      expect(new_b.properties["email"].type).to eq("string")
    end

    it "preserves existing properties" do
      existing = described_class.new(type: "string")
      builder = described_class.new(type: "object", properties: { "name" => existing })
      new_b = builder.add_property("email")
      expect(new_b.properties.keys).to contain_exactly("name", "email")
    end

    it "does not mutate the original" do
      builder = described_class.new(type: "object")
      builder.add_property("email")
      expect(builder.properties).to be_empty
    end

    it "does not overwrite an existing property" do
      age_b = described_class.new(type: "integer")
      builder = described_class.new(type: "object", properties: { "age" => age_b })
      new_b = builder.add_property("age")
      expect(new_b.properties["age"].type).to eq("integer")
    end

    it "ignores blank name" do
      builder = described_class.new(type: "object")
      new_b = builder.add_property("")
      expect(new_b.properties).to be_empty
    end
  end

  describe "#remove_property" do
    it "removes the named property" do
      name_b = described_class.new(type: "string")
      builder = described_class.new(type: "object", properties: { "name" => name_b, "age" => name_b })
      new_b = builder.remove_property("name")
      expect(new_b.properties.keys).to eq([ "age" ])
    end

    it "also removes from required" do
      name_b = described_class.new(type: "string")
      builder = described_class.new(
        type: "object",
        required: [ "name" ],
        properties: { "name" => name_b }
      )
      new_b = builder.remove_property("name")
      expect(new_b.required).to be_empty
    end
  end

  describe "#with_type" do
    it "returns a new builder with the new type" do
      builder = described_class.new(
        type: "object",
        description: "Desc",
        properties: { "x" => described_class.new(type: "string") }
      )
      new_b = builder.with_type("string")
      expect(new_b.type).to eq("string")
    end

    it "preserves description" do
      builder = described_class.new(type: "object", description: "Desc")
      expect(builder.with_type("string").description).to eq("Desc")
    end

    it "drops incompatible keys (object → string clears properties and required)" do
      name_b = described_class.new(type: "string")
      builder = described_class.new(
        type: "object",
        required: [ "name" ],
        properties: { "name" => name_b }
      )
      new_b = builder.with_type("string")
      expect(new_b.properties).to be_empty
      expect(new_b.required).to be_empty
    end
  end

  describe "#with_mutation" do
    it "applies block to self when path is empty" do
      builder = described_class.new(type: "object")
      result = builder.with_mutation([]) { |b| b.add_property("x") }
      expect(result.properties.keys).to eq([ "x" ])
    end

    it "applies block to nested property" do
      name_b = described_class.new(type: "string")
      address_b = described_class.new(type: "object", properties: {})
      root = described_class.new(
        type: "object",
        properties: { "name" => name_b, "address" => address_b }
      )
      result = root.with_mutation(%w[properties address]) { |b| b.add_property("street") }
      expect(result.properties["address"].properties.keys).to eq([ "street" ])
      expect(result.properties["name"].type).to eq("string")
    end

    it "applies block to array items" do
      items_b = described_class.new(type: "string")
      root = described_class.new(type: "array", items: items_b)
      result = root.with_mutation([ "items" ]) { |b| b.with_type("integer") }
      expect(result.items.type).to eq("integer")
    end

    it "defaults nil items to string type so enum changes are not silently dropped" do
      root = described_class.new(type: "array")
      result = root.with_mutation([ "items" ]) { |b| b }
      expect(result.items.type).to eq("string")
    end

    it "preserves enum values applied to nil items" do
      root = described_class.new(type: "array")
      result = root.with_mutation([ "items" ]) do |b|
        described_class.from_schema(b.to_schema.merge("enum" => %w[pending done]))
      end
      expect(result.to_schema.dig("items", "enum")).to eq(%w[pending done])
    end
  end
end
