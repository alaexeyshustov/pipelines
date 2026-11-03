require 'rails_helper'

RSpec.describe Orchestration::Executors::Query do
  describe '.call' do
    before do
      create(:interview, company: 'Acme',    status: 'pending_reply')
      create(:interview, company: 'Globex',  status: 'rejected')
      create(:interview, company: 'Initech', status: 'pending_reply')
    end

    context 'when filtering by a single value' do
      it 'returns only matching records under the table key' do
        result = described_class.call(
          table: "interviews", column_name: "status", column_values: [ "pending_reply" ]
        )
        expect(result.keys).to eq([ "interviews" ])
        expect(result["interviews"].pluck("company")).to contain_exactly('Acme', 'Initech')
      end

      it 'returns records as hashes with string keys' do
        result = described_class.call(
          table: "interviews", column_name: "status", column_values: [ "pending_reply" ]
        )
        expect(result["interviews"].first).to be_a(Hash)
        expect(result["interviews"].first.keys).to all(be_a(String))
      end
    end

    context 'when filtering by multiple values' do
      it 'returns all records matching any of the values' do
        result = described_class.call(
          table: "interviews", column_name: "company", column_values: [ "Acme", "Globex" ]
        )
        expect(result["interviews"].pluck("company")).to contain_exactly('Acme', 'Globex')
      end
    end

    context 'when columns is specified' do
      it 'returns only the specified columns' do
        result = described_class.call(
          table: "interviews", column_name: "status",
          column_values: [ "rejected" ], columns: [ "company", "status" ]
        )
        expect(result["interviews"].first.keys).to contain_exactly("company", "status")
      end
    end

    context 'when columns is absent' do
      it 'returns all columns' do
        result = described_class.call(
          table: "interviews", column_name: "status", column_values: [ "rejected" ]
        )
        expect(result["interviews"].first.keys).to include("id", "company", "status", "applied_at")
      end
    end

    context 'when no records match' do
      it 'returns an empty array under the table key' do
        result = described_class.call(
          table: "interviews", column_name: "company", column_values: [ "Unknown" ]
        )
        expect(result["interviews"]).to eq([])
      end
    end

    context 'when the table is unknown' do
      it 'raises ArgumentError' do
        expect {
          described_class.call(table: "nonexistent_table", column_name: "id", column_values: [ 1 ])
        }.to raise_error(ArgumentError, /Unknown table/)
      end
    end

    describe '.input_schema' do
      it 'returns a JSON Schema with required fields' do
        schema = described_class.input_schema
        expect(schema["type"]).to eq("object")
        expect(schema["required"]).to include("table", "column_name", "column_values")
      end

      it 'declares columns as optional' do
        schema = described_class.input_schema
        expect(schema["required"]).not_to include("columns")
        expect(schema["properties"].keys).to include("columns")
      end
    end
  end
end
