require 'rails_helper'

RSpec.describe Orchestration::QueryExecutor do
  describe '.call' do
    let!(:acme)    { create(:application_mail, company: 'Acme',   provider: 'gmail') }
    let!(:globex)  { create(:application_mail, company: 'Globex', provider: 'yahoo') }
    let!(:initech) { create(:application_mail, company: 'Initech', provider: 'gmail') }

    context 'when filtering by a single value' do
      it 'returns only matching records under the table key' do
        result = described_class.call(
          table: "application_mails", column_name: "provider", column_values: [ "gmail" ]
        )
        expect(result.keys).to eq([ "application_mails" ])
        expect(result["application_mails"].map { _1["company"] }).to contain_exactly('Acme', 'Initech')
      end

      it 'returns records as hashes with string keys' do
        result = described_class.call(
          table: "application_mails", column_name: "provider", column_values: [ "gmail" ]
        )
        expect(result["application_mails"].first).to be_a(Hash)
        expect(result["application_mails"].first.keys).to all(be_a(String))
      end
    end

    context 'when filtering by multiple values' do
      it 'returns all records matching any of the values' do
        result = described_class.call(
          table: "application_mails", column_name: "company", column_values: [ "Acme", "Globex" ]
        )
        expect(result["application_mails"].map { _1["company"] }).to contain_exactly('Acme', 'Globex')
      end
    end

    context 'when columns is specified' do
      it 'returns only the specified columns' do
        result = described_class.call(
          table: "application_mails", column_name: "provider",
          column_values: [ "yahoo" ], columns: [ "company", "provider" ]
        )
        expect(result["application_mails"].first.keys).to contain_exactly("company", "provider")
      end
    end

    context 'when columns is absent' do
      it 'returns all columns' do
        result = described_class.call(
          table: "application_mails", column_name: "provider", column_values: [ "yahoo" ]
        )
        expect(result["application_mails"].first.keys).to include("id", "company", "provider", "action")
      end
    end

    context 'when no records match' do
      it 'returns an empty array under the table key' do
        result = described_class.call(
          table: "application_mails", column_name: "company", column_values: [ "Unknown" ]
        )
        expect(result["application_mails"]).to eq([])
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
