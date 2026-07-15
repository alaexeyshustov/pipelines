# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::SchemaBuilderParamsForm do
  def build_form(params = {})
    described_class.new(ActionController::Parameters.new(params).permit!)
  end

  describe "#apply" do
    it "sets a description" do
      node = Orchestration::SchemaBuilder.new(type: "string")
      result = build_form(description: "Full name").apply(node)
      expect(result.description).to eq("Full name")
    end

    it "clears the description when blank" do
      node = Orchestration::SchemaBuilder.new(type: "string", description: "Full name")
      result = build_form(description: "").apply(node)
      expect(result.description).to be_nil
    end

    it "leaves the description untouched when the key is absent" do
      node = Orchestration::SchemaBuilder.new(type: "string", description: "Full name")
      result = build_form({}).apply(node)
      expect(result.description).to eq("Full name")
    end

    it "sets a format" do
      node = Orchestration::SchemaBuilder.new(type: "string")
      result = build_form(format: "date").apply(node)
      expect(result.format).to eq("date")
    end

    it "clears a format when blank" do
      node = Orchestration::SchemaBuilder.new(type: "string", format: "date")
      result = build_form(format: "").apply(node)
      expect(result.format).to be_nil
    end

    it "coerces integer enum values" do
      node = Orchestration::SchemaBuilder.new(type: "integer")
      result = build_form(enum_text: "1\n2\n3").apply(node)
      expect(result.enum).to eq([ 1, 2, 3 ])
    end

    it "coerces number enum values" do
      node = Orchestration::SchemaBuilder.new(type: "number")
      result = build_form(enum_text: "1.5\n2.5").apply(node)
      expect(result.enum).to eq([ 1.5, 2.5 ])
    end

    it "keeps string enum values as strings" do
      node = Orchestration::SchemaBuilder.new(type: "string")
      result = build_form(enum_text: "pending\ndone").apply(node)
      expect(result.enum).to eq(%w[pending done])
    end

    it "clears the enum when the text is blank" do
      node = Orchestration::SchemaBuilder.new(type: "string", enum: %w[a b])
      result = build_form(enum_text: "").apply(node)
      expect(result.enum).to eq([])
    end

    it "sets an integer minimum" do
      node = Orchestration::SchemaBuilder.new(type: "integer")
      result = build_form(minimum: "5").apply(node)
      expect(result.minimum).to eq(5)
    end

    it "sets a float maximum for number type" do
      node = Orchestration::SchemaBuilder.new(type: "number")
      result = build_form(maximum: "5.5").apply(node)
      expect(result.maximum).to eq(5.5)
    end

    it "clears minimum when blank" do
      node = Orchestration::SchemaBuilder.new(type: "integer", minimum: 5)
      result = build_form(minimum: "").apply(node)
      expect(result.minimum).to be_nil
    end

    it "adds a property to the required list when checked" do
      node = Orchestration::SchemaBuilder.new(type: "object", properties: { "name" => Orchestration::SchemaBuilder.new(type: "string") })
      result = build_form(required_toggle: "name", required_checked: "true").apply(node)
      expect(result.required).to eq([ "name" ])
    end

    it "removes a property from the required list when unchecked" do
      node = Orchestration::SchemaBuilder.new(
        type: "object",
        properties: { "name" => Orchestration::SchemaBuilder.new(type: "string") },
        required: [ "name" ]
      )
      result = build_form(required_toggle: "name", required_checked: "false").apply(node)
      expect(result.required).to eq([])
    end

    it "sets additionalProperties when the toggle is present" do
      node = Orchestration::SchemaBuilder.new(type: "object")
      result = build_form(additional_properties_toggle: "true", additional_properties: "true").apply(node)
      expect(result.additional_properties).to be true
    end

    it "ignores additionalProperties when the toggle is absent" do
      node = Orchestration::SchemaBuilder.new(type: "object", additional_properties: true)
      result = build_form(additional_properties: "false").apply(node)
      expect(result.additional_properties).to be true
    end
  end
end
