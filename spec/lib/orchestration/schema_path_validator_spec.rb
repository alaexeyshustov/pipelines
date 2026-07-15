require 'rails_helper'

RSpec.describe Orchestration::SchemaPathValidator do
  describe '.valid?' do
    context 'with a top-level property path' do
      let(:schema) do
        {
          "type" => "object",
          "properties" => { "result" => { "type" => "string" } }
        }
      end

      it 'returns true when the path resolves' do
        expect(described_class.valid?("result", schema)).to be true
      end

      it 'returns false when the path does not resolve' do
        expect(described_class.valid?("nonexistent", schema)).to be false
      end
    end

    context 'with a nested object path' do
      let(:schema) do
        {
          "type" => "object",
          "properties" => {
            "data" => {
              "type" => "object",
              "properties" => { "name" => { "type" => "string" } }
            }
          }
        }
      end

      it 'returns true when the nested path resolves' do
        expect(described_class.valid?("data.name", schema)).to be true
      end

      it 'returns false when the nested path does not resolve' do
        expect(described_class.valid?("data.missing", schema)).to be false
      end

      it 'returns false when an intermediate segment does not resolve' do
        expect(described_class.valid?("missing.name", schema)).to be false
      end
    end

    context 'with an array path' do
      let(:schema) do
        {
          "type" => "object",
          "properties" => {
            "items" => {
              "type" => "array",
              "items" => { "type" => "object", "properties" => { "id" => { "type" => "string" } } }
            }
          }
        }
      end

      it 'returns true when the numeric index segment resolves into array items' do
        expect(described_class.valid?("items.0.id", schema)).to be true
      end

      it 'returns false when the array segment is not numeric' do
        expect(described_class.valid?("items.first.id", schema)).to be false
      end

      it 'returns false when items has no schema and a further segment is requested' do
        array_schema = { "type" => "object", "properties" => { "items" => { "type" => "array" } } }
        expect(described_class.valid?("items.0.id", array_schema)).to be false
      end

      it 'returns false when the path ends at a numeric segment for an array with no items schema' do
        array_schema = { "type" => "object", "properties" => { "items" => { "type" => "array" } } }
        expect(described_class.valid?("items.0", array_schema)).to be false
      end
    end

    context 'with a scalar type in the middle of the path' do
      let(:schema) do
        {
          "type" => "object",
          "properties" => { "name" => { "type" => "string" } }
        }
      end

      it 'returns false when trying to traverse past a scalar' do
        expect(described_class.valid?("name.extra", schema)).to be false
      end
    end

    context 'with an empty schema' do
      it 'returns false' do
        expect(described_class.valid?("anything", {})).to be false
      end
    end
  end
end
