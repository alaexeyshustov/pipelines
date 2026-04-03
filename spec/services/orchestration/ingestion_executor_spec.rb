require 'rails_helper'

RSpec.describe Orchestration::IngestionExecutor do
  describe '.call' do
    let(:emails) do
      [
        { "id" => "e1", "subject" => "Applied at Acme",    "body" => "body1" },
        { "id" => "e2", "subject" => "Rejected at Globex", "body" => "body2" },
        { "id" => "e3", "subject" => "Interview at Initech", "body" => "body3" }
      ]
    end

    let(:filter_result) { [ { "id" => "e1" }, { "id" => "e3" } ] }
    let(:input)         { { "emails" => emails, "result" => filter_result } }

    context 'when filtering by ids' do
      let(:params) do
        {
          "operations" => [
            { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" }
          ]
        }
      end

      it 'keeps only emails whose id appears in ids_from' do
        result = described_class.call(input, params)
        expect(result["emails"].map { _1["id"] }).to eq(%w[e1 e3])
      end

      it 'retains full email objects, not just ids' do
        result = described_class.call(input, params)
        expect(result["emails"].first).to include("subject", "body")
      end

      it 'matches when ids_from contains integer ids but source has string ids' do
        int_filter = [ { "id" => 1 }, { "id" => 3 } ]
        str_emails = [
          { "id" => "1", "subject" => "A" },
          { "id" => "2", "subject" => "B" },
          { "id" => "3", "subject" => "C" }
        ]
        result = described_class.call({ "emails" => str_emails, "result" => int_filter }, params)
        expect(result["emails"].map { _1["id"] }).to eq(%w[1 3])
      end

      it 'does not mutate the original input' do
        original = input.dup
        described_class.call(input, params)
        expect(input).to eq(original)
      end
    end

    context 'when filtering by ids with a dotted ids_from path' do
      let(:nested_input) do
        {
          "emails" => emails,
          "result" => { "results" => filter_result }
        }
      end
      let(:params) do
        {
          "operations" => [
            { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result.results", "output" => "emails" }
          ]
        }
      end

      it 'digs into the nested structure to resolve the id list' do
        result = described_class.call(nested_input, params)
        expect(result["emails"].map { _1["id"] }).to eq(%w[e1 e3])
      end
    end

    context 'when renaming a key' do
      let(:params) do
        {
          "operations" => [
            { "type" => "rename", "from" => "emails", "to" => "messages" }
          ]
        }
      end

      it 'renames the key' do
        result = described_class.call(input, params)
        expect(result).to have_key("messages")
        expect(result).not_to have_key("emails")
      end
    end

    context 'when picking keys' do
      let(:params) do
        {
          "operations" => [
            { "type" => "pick", "keys" => [ "emails" ] }
          ]
        }
      end

      it 'keeps only the specified keys' do
        result = described_class.call(input, params)
        expect(result.keys).to eq([ "emails" ])
      end
    end

    context 'with sequential operations (filter_by_ids then pick)' do
      let(:params) do
        {
          "operations" => [
            { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" },
            { "type" => "pick", "keys" => [ "emails" ] }
          ]
        }
      end

      it 'applies operations in order and returns only filtered emails' do
        result = described_class.call(input, params)
        expect(result.keys).to eq([ "emails" ])
        expect(result["emails"].map { _1["id"] }).to eq(%w[e1 e3])
      end
    end

    context 'when params has no operations key' do
      it 'returns the input unchanged' do
        result = described_class.call(input, {})
        expect(result).to eq(input)
      end
    end

    context 'when params is absent (single-arg call)' do
      it 'returns the input unchanged' do
        result = described_class.call(input)
        expect(result).to eq(input)
      end
    end

    context 'when merging by index' do
      let(:merge_input) do
        {
          "emails"     => [ { "email_id" => "19d4", "company" => "Bilendo" },
                            { "email_id" => "abcd", "company" => "Foo" } ],
          "stored_ids" => [ 986, 987 ]
        }
      end
      let(:params) do
        {
          "operations" => [
            { "type" => "merge_by_index", "source" => "emails", "ids" => "stored_ids", "inject" => "id", "output" => "records" }
          ]
        }
      end

      it 'zips source objects with ids, injecting the id field into each object' do
        result = described_class.call(merge_input, params)
        expect(result["records"]).to eq([
          { "id" => 986, "email_id" => "19d4", "company" => "Bilendo" },
          { "id" => 987, "email_id" => "abcd", "company" => "Foo" }
        ])
      end

      it 'truncates to the shorter array when source is longer than ids' do
        long_source = merge_input["emails"] + [ { "email_id" => "extra", "company" => "Extra" } ]
        result = described_class.call({ "emails" => long_source, "stored_ids" => merge_input["stored_ids"] }, params)
        expect(result["records"].length).to eq(2)
        expect(result["records"].map { _1["id"] }).to eq([ 986, 987 ])
      end

      it 'truncates to the shorter array when ids is longer than source' do
        long_ids = merge_input["stored_ids"] + [ 999 ]
        result = described_class.call({ "emails" => merge_input["emails"], "stored_ids" => long_ids }, params)
        expect(result["records"].length).to eq(2)
        expect(result["records"].map { _1["id"] }).to eq([ 986, 987 ])
      end

      it 'returns empty records when source is nil' do
        result = described_class.call({ "emails" => nil, "stored_ids" => merge_input["stored_ids"] }, params)
        expect(result["records"]).to eq([])
      end

      it 'returns empty records when ids is nil' do
        result = described_class.call({ "emails" => merge_input["emails"], "stored_ids" => nil }, params)
        expect(result["records"]).to eq([])
      end
    end

    context 'when an unknown operation type is given' do
      let(:params) { { "operations" => [ { "type" => "explode" } ] } }

      it 'raises ArgumentError with the unknown type' do
        expect { described_class.call(input, params) }
          .to raise_error(ArgumentError, /unknown operation type: explode/)
      end
    end
  end
end
