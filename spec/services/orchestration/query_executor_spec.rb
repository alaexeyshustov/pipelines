require 'rails_helper'

RSpec.describe Orchestration::QueryExecutor do
  describe '.call' do
    let!(:acme)   { create(:application_mail, company: 'Acme',   provider: 'gmail') }
    let!(:globex) { create(:application_mail, company: 'Globex', provider: 'yahoo') }
    let!(:initech) { create(:application_mail, company: 'Initech', provider: 'gmail') }

    let(:input) { {} }

    context 'when filtering by a single value' do
      let(:params) do
        { "table" => "application_mails", "column_name" => "provider", "column_values" => [ "gmail" ] }
      end

      it 'returns only matching records under the table key' do
        result = described_class.call(input, params)
        expect(result.keys).to eq([ "application_mails" ])
        expect(result["application_mails"].map { _1["company"] }).to contain_exactly('Acme', 'Initech')
      end

      it 'returns records as hashes with string keys' do
        result = described_class.call(input, params)
        expect(result["application_mails"].first).to be_a(Hash)
        expect(result["application_mails"].first.keys).to all(be_a(String))
      end
    end

    context 'when filtering by multiple values' do
      let(:params) do
        { "table" => "application_mails", "column_name" => "company", "column_values" => [ "Acme", "Globex" ] }
      end

      it 'returns all records matching any of the values' do
        result = described_class.call(input, params)
        expect(result["application_mails"].map { _1["company"] }).to contain_exactly('Acme', 'Globex')
      end
    end

    context 'when columns param is specified' do
      let(:params) do
        {
          "table"         => "application_mails",
          "column_name"   => "provider",
          "column_values" => [ "yahoo" ],
          "columns"       => [ "company", "provider" ]
        }
      end

      it 'returns only the specified columns' do
        result = described_class.call(input, params)
        expect(result["application_mails"].first.keys).to contain_exactly("company", "provider")
      end
    end

    context 'when columns param is absent' do
      let(:params) do
        { "table" => "application_mails", "column_name" => "provider", "column_values" => [ "yahoo" ] }
      end

      it 'returns all columns' do
        result = described_class.call(input, params)
        expect(result["application_mails"].first.keys).to include("id", "company", "provider", "action")
      end
    end

    context 'when no records match' do
      let(:params) do
        { "table" => "application_mails", "column_name" => "company", "column_values" => [ "Unknown" ] }
      end

      it 'returns an empty array under the table key' do
        result = described_class.call(input, params)
        expect(result["application_mails"]).to eq([])
      end
    end

    context 'when column_values_from is used instead of column_values' do
      let(:params) do
        { "table" => "application_mails", "column_name" => "id", "column_values_from" => "stored_ids" }
      end

      it 'reads ids from the input and returns matching records' do
        result = described_class.call({ "stored_ids" => [ acme.id, initech.id ] }, params)
        expect(result["application_mails"].map { _1["company"] }).to contain_exactly('Acme', 'Initech')
      end

      it 'supports a dotted path in column_values_from' do
        result = described_class.call({ "result" => { "ids" => [ globex.id ] } },
                                      params.merge("column_values_from" => "result.ids"))
        expect(result["application_mails"].map { _1["company"] }).to eq([ 'Globex' ])
      end

      it 'returns empty array when the path resolves to nil' do
        result = described_class.call({}, params)
        expect(result["application_mails"]).to eq([])
      end
    end

    context 'when the table is unknown' do
      let(:params) do
        { "table" => "nonexistent_table", "column_name" => "id", "column_values" => [ 1 ] }
      end

      it 'raises ArgumentError' do
        expect { described_class.call(input, params) }
          .to raise_error(ArgumentError, /Unknown table/)
      end
    end

    context 'when a required param is missing' do
      it 'raises KeyError for missing table' do
        expect { described_class.call(input, { "column_name" => "id", "column_values" => [ 1 ] }) }
          .to raise_error(KeyError)
      end

      it 'raises KeyError for missing column_name' do
        expect { described_class.call(input, { "table" => "application_mails", "column_values" => [ 1 ] }) }
          .to raise_error(KeyError)
      end

      it 'raises KeyError for missing column_values' do
        expect { described_class.call(input, { "table" => "application_mails", "column_name" => "id" }) }
          .to raise_error(KeyError)
      end
    end
  end
end
