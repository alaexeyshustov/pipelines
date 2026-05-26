require 'rails_helper'

RSpec.describe Orchestration::Executable do
  def make_executor(&block)
    Class.new do
      include Orchestration::Executable
      class_eval(&block)
    end
  end

  describe '.input_schema' do
    context 'with a valid declaration covering all keyword args' do
      subject(:schema) do
        make_executor do
          input_schema(
            date:      { "type" => "string" },
            providers: { "type" => "array", "items" => { "type" => "string" } }
          )
          def self.call(date:, providers: [], **); end
        end.input_schema
      end

      it 'returns type object at top level' do
        expect(schema["type"]).to eq("object")
      end

      it 'includes all declared properties' do
        expect(schema["properties"].keys).to contain_exactly("date", "providers")
      end

      it 'lists only keyreq params as required' do
        expect(schema["required"]).to eq(["date"])
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
          def self.call(date:, topic:, **); end
        end

        expect { klass.input_schema }.to raise_error(ArgumentError, /topic/)
      end
    end

    context 'when a declared type has no matching keyword arg' do
      it 'raises ArgumentError at schema access time' do
        klass = make_executor do
          input_schema(date: { "type" => "string" }, ghost: { "type" => "string" })
          def self.call(date:, **); end
        end

        expect { klass.input_schema }.to raise_error(ArgumentError, /ghost/)
      end
    end

    context 'when input_schema is not declared' do
      it 'returns nil' do
        klass = make_executor { def self.call(**); end }
        expect(klass.input_schema).to be_nil
      end
    end

    context 'when there are no keyword args (only **)' do
      it 'raises ArgumentError when types are declared but no keyword args exist' do
        klass = make_executor do
          input_schema(date: { "type" => "string" })
          def self.call(**); end
        end

        expect { klass.input_schema }.to raise_error(ArgumentError, /date/)
      end
    end
  end
end
