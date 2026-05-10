require 'rails_helper'

RSpec.describe Orchestration::SchemaValidator do
  subject(:validator) { described_class.new(schema) }

  describe '#validate!' do
    context 'when schema is nil' do
      let(:schema) { nil }

      it 'passes any input' do
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

      it 'passes when data matches' do
        expect { validator.validate!({ "result" => [ 1, 2, 3 ] }) }.not_to raise_error
      end

      it 'raises when a required key is missing' do
        expect { validator.validate!({}) }
          .to raise_error(described_class::Error, /missing required key: result/)
      end

      it 'raises when the property type is wrong' do
        expect { validator.validate!({ "result" => "a string" }) }
          .to raise_error(described_class::Error, /data\.result must be an array/)
      end

      it 'raises when the top-level value is not an object' do
        expect { validator.validate!([]) }
          .to raise_error(described_class::Error, /data must be an object/)
      end
    end

    context 'with an array schema' do
      let(:schema) { { "type" => "array" } }

      it 'passes for an array' do
        expect { validator.validate!([]) }.not_to raise_error
      end

      it 'raises for a non-array' do
        expect { validator.validate!("text") }
          .to raise_error(described_class::Error, /data must be an array/)
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

    context 'with a nil property sub-schema' do
      let(:schema) do
        { "type" => "object", "properties" => { "result" => nil } }
      end

      it 'does not raise when the property exists but its sub-schema is nil' do
        expect { validator.validate!({ "result" => "anything" }) }.not_to raise_error
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

    context 'with integer type' do
      let(:schema) { { "type" => "object", "properties" => { "count" => { "type" => "integer" } } } }

      it 'passes for an integer' do
        expect { validator.validate!({ "count" => 42 }) }.not_to raise_error
      end

      it 'raises for a float' do
        expect { validator.validate!({ "count" => 1.5 }) }
          .to raise_error(described_class::Error, /must be an integer/)
      end
    end

    context 'with number type' do
      let(:schema) { { "type" => "object", "properties" => { "score" => { "type" => "number" } } } }

      it 'passes for a float' do
        expect { validator.validate!({ "score" => 1.5 }) }.not_to raise_error
      end

      it 'passes for an integer' do
        expect { validator.validate!({ "score" => 42 }) }.not_to raise_error
      end

      it 'raises for a non-numeric' do
        expect { validator.validate!({ "score" => "high" }) }
          .to raise_error(described_class::Error, /must be a number/)
      end
    end

    context 'with boolean type' do
      let(:schema) { { "type" => "object", "properties" => { "flag" => { "type" => "boolean" } } } }

      it 'passes for true' do
        expect { validator.validate!({ "flag" => true }) }.not_to raise_error
      end

      it 'passes for false' do
        expect { validator.validate!({ "flag" => false }) }.not_to raise_error
      end

      it 'raises for a non-boolean' do
        expect { validator.validate!({ "flag" => "yes" }) }
          .to raise_error(described_class::Error, /must be a boolean/)
      end
    end
  end
end
