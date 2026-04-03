require 'rails_helper'

RSpec.describe Orchestration::InputMappingResolver do
  subject(:resolver) { described_class.new(input_mapping: input_mapping, previous_outputs: previous_outputs) }

  let(:previous_outputs) do
    [
      { "step_name" => "extract", "output" => { "text" => "hello", "count" => 1 } },
      { "step_name" => "extract", "output" => { "text" => "world", "count" => 2 } }
    ]
  end

  describe '#resolve' do
    context 'when input_mapping is nil' do
      let(:input_mapping) { nil }

      it 'merges all outputs into a single hash' do
        result = resolver.resolve
        expect(result).to eq({ "text" => "world", "count" => 2 })
      end
    end

    context 'when input_mapping is nil and previous_outputs is empty' do
      let(:input_mapping) { nil }
      let(:previous_outputs) { [] }

      it 'returns an empty hash' do
        expect(resolver.resolve).to eq({})
      end
    end

    context 'with explicit input_mapping using merge concat' do
      let(:input_mapping) do
        {
          "combined_text" => { "from_step" => "extract", "path" => "text", "merge" => "concat" }
        }
      end

      it 'concatenates values from the specified step and path' do
        result = resolver.resolve
        expect(result["combined_text"]).to eq("hello\nworld")
      end
    end

    context 'with explicit mapping referencing a missing path' do
      let(:input_mapping) do
        {
          "missing_key" => { "from_step" => "extract", "path" => "nonexistent", "merge" => "concat" }
        }
      end

      it 'returns an empty string for missing keys' do
        expect(resolver.resolve["missing_key"]).to eq("")
      end
    end

    context 'with explicit mapping referencing an unknown step' do
      let(:input_mapping) do
        {
          "data" => { "from_step" => "unknown_step", "path" => "text", "merge" => "concat" }
        }
      end

      it 'returns an empty string for unknown steps' do
        expect(resolver.resolve["data"]).to eq("")
      end
    end

    context 'with explicit mapping without merge strategy' do
      let(:input_mapping) do
        {
          "last_count" => { "from_step" => "extract", "path" => "count" }
        }
      end

      it 'returns the last matching value' do
        expect(resolver.resolve["last_count"]).to eq(2)
      end
    end

    context 'with a static value' do
      let(:input_mapping) do
        {
          "destination_table"    => { "value" => "application_mails" },
          "columns_to_normalize" => { "value" => [ "company", "job_title" ] }
        }
      end

      it 'returns the literal value without consulting previous_outputs' do
        result = resolver.resolve
        expect(result["destination_table"]).to eq("application_mails")
        expect(result["columns_to_normalize"]).to eq([ "company", "job_title" ])
      end
    end

    context 'with a dotted path' do
      let(:previous_outputs) do
        [
          { "step_name" => "store", "output" => { "result" => { "ids" => [ 1, 2, 3 ] } } }
        ]
      end
      let(:input_mapping) do
        { "stored_ids" => { "from_step" => "store", "path" => "result.ids" } }
      end

      it 'digs into nested output keys' do
        expect(resolver.resolve["stored_ids"]).to eq([ 1, 2, 3 ])
      end
    end
  end
end
