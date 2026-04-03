require 'rails_helper'

RSpec.describe Orchestration::OutputValidator do
  subject(:validator) { described_class.new(schema) }

  describe '#validate!' do
    context 'when schema is nil' do
      let(:schema) { nil }

      it 'passes any output' do
        expect { validator.validate!({ "result" => "anything" }) }.not_to raise_error
      end
    end

    context 'with an object schema' do
      let(:schema) do
        {
          "type" => "object",
          "required" => [ "result" ],
          "properties" => {
            "result" => { "type" => "array" }
          }
        }
      end

      it 'passes when output matches' do
        expect { validator.validate!({ "result" => [ 1, 2, 3 ] }) }.not_to raise_error
      end

      it 'raises when a required key is missing' do
        expect { validator.validate!({}) }
          .to raise_error(described_class::Error, /missing required key: result/)
      end

      it 'raises when the property type is wrong' do
        expect { validator.validate!({ "result" => "a string" }) }
          .to raise_error(described_class::Error, /output\.result must be an array/)
      end

      it 'raises when the top-level value is not an object' do
        expect { validator.validate!([]) }
          .to raise_error(described_class::Error, /output must be an object/)
      end
    end

    context 'with an array schema' do
      let(:schema) { { "type" => "array" } }

      it 'passes for an array' do
        expect { validator.validate!([]) }.not_to raise_error
      end

      it 'raises for a non-array' do
        expect { validator.validate!("text") }
          .to raise_error(described_class::Error, /output must be an array/)
      end
    end

    context 'with nested array items schema' do
      let(:schema) do
        {
          "type" => "object",
          "properties" => {
            "result" => {
              "type" => "array",
              "items" => { "type" => "object", "required" => [ "id" ] }
            }
          }
        }
      end

      it 'raises when an item is missing a required key' do
        expect { validator.validate!({ "result" => [ {} ] }) }
          .to raise_error(described_class::Error, /missing required key: id/)
      end

      it 'passes when all items are valid' do
        expect { validator.validate!({ "result" => [ { "id" => 1 } ] }) }.not_to raise_error
      end
    end

    context 'with string type' do
      let(:schema) { { "type" => "object", "properties" => { "result" => { "type" => "string" } } } }

      it 'passes for a string value' do
        expect { validator.validate!({ "result" => "ok" }) }.not_to raise_error
      end

      it 'raises for a non-string' do
        expect { validator.validate!({ "result" => 42 }) }
          .to raise_error(described_class::Error, /must be a string/)
      end
    end
  end
end
