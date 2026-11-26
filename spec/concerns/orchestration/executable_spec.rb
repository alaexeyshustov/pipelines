require 'rails_helper'

RSpec.describe Orchestration::Executable do
  def make_executor(&block)
    stub_const("ExecutableHost", Class.new do
      include Orchestration::Executable
      class_eval(&block)
    end)
  end

  describe '.input_schema' do
    context 'with a valid declaration covering all keyword args' do
      subject(:schema) do
        make_executor do
          input_schema(
            date:      { "type" => "string" },
            providers: { "type" => "array", "items" => { "type" => "string" } }
          )
          def initialize(date:, providers: [], **); end
        end.input_schema
      end

      it 'returns type object at top level' do
        expect(schema["type"]).to eq("object")
      end

      it 'includes all declared properties' do
        expect(schema["properties"].keys).to contain_exactly("date", "providers")
      end

      it 'lists only keyreq params as required' do
        expect(schema["required"]).to eq([ "date" ])
      end

      it 'preserves nested type definitions' do
        expect(schema["properties"]["providers"]).to eq(
          "type" => "array", "items" => { "type" => "string" }
        )
      end
    end

    context 'when a required keyword arg has no declared type' do
      it 'raises ArgumentError at schema access time' do
        klass = make_executor do
          input_schema(date: { "type" => "string" })
          def initialize(date:, topic:, **); end
        end

        expect { klass.input_schema }.to raise_error(ArgumentError, /topic/)
      end
    end

    context 'when a declared type has no matching keyword arg' do
      it 'raises ArgumentError at schema access time' do
        klass = make_executor do
          input_schema(date: { "type" => "string" }, ghost: { "type" => "string" })
          def initialize(date:, **); end
        end

        expect { klass.input_schema }.to raise_error(ArgumentError, /ghost/)
      end
    end

    context 'when input_schema is not declared' do
      it 'returns nil' do
        klass = make_executor { def initialize(**); end }
        expect(klass.input_schema).to be_nil
      end
    end

    context 'when there are no keyword args (only **)' do
      it 'raises ArgumentError when types are declared but no keyword args exist' do
        klass = make_executor do
          input_schema(date: { "type" => "string" })
          def initialize(**); end
        end

        expect { klass.input_schema }.to raise_error(ArgumentError, /date/)
      end
    end
  end

  describe '.output_schema' do
    it 'returns nil when output_schema is not declared' do
      klass = make_executor { def initialize(**); end }
      expect(klass.output_schema).to be_nil
    end

    context 'with a declaration' do
      subject(:schema) do
        make_executor do
          output_schema(
            tagged: { "type" => "array", "items" => { "type" => "integer" } },
            failed: { type: "array", items: { type: "object" } }
          )
          def initialize(**); end
        end.output_schema
      end

      it 'builds an object schema with the declared properties' do
        expect(schema).to include("type" => "object")
        expect(schema["properties"].keys).to contain_exactly("tagged", "failed")
      end

      it 'requires every declared key' do
        expect(schema["required"]).to contain_exactly("tagged", "failed")
      end

      it 'stringifies nested keys' do
        expect(schema["properties"]["failed"]).to eq("type" => "array", "items" => { "type" => "object" })
      end
    end

    it 'is not checked against the initialize keywords' do
      klass = make_executor do
        output_schema(ids: { "type" => "array" })
        def initialize(date:, **); end
      end

      expect { klass.output_schema }.not_to raise_error
    end

    it 'is independent of input_schema' do
      klass = make_executor do
        input_schema(date: { "type" => "string" })
        output_schema(ids: { "type" => "array" })
        def initialize(date:, **); end
      end

      expect(klass.input_schema["properties"].keys).to eq([ "date" ])
      expect(klass.output_schema["properties"].keys).to eq([ "ids" ])
    end
  end
end
