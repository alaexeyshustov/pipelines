require 'rails_helper'

RSpec.describe Orchestration::IngestionExecutor do
  def call(input = {}, operations: [])
    described_class.call(operations:, **input.transform_keys(&:to_sym))
  end

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
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" } ]
      end

      it 'keeps only emails whose id appears in ids_from' do
        result = call(input, operations:)
        expect(result["emails"].map { _1["id"] }).to eq(%w[e1 e3])
      end

      it 'retains full email objects, not just ids' do
        result = call(input, operations:)
        expect(result["emails"].first).to include("subject", "body")
      end

      it 'matches when ids_from contains integer ids but source has string ids' do
        int_filter = [ { "id" => 1 }, { "id" => 3 } ]
        str_emails = [
          { "id" => "1", "subject" => "A" },
          { "id" => "2", "subject" => "B" },
          { "id" => "3", "subject" => "C" }
        ]
        result = call({ "emails" => str_emails, "result" => int_filter }, operations:)
        expect(result["emails"].map { _1["id"] }).to eq(%w[1 3])
      end

      it 'does not mutate the original input' do
        original = input.dup
        call(input, operations:)
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
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result.results", "output" => "emails" } ]
      end

      it 'digs into the nested structure to resolve the id list' do
        result = call(nested_input, operations:)
        expect(result["emails"].map { _1["id"] }).to eq(%w[e1 e3])
      end
    end

    context 'when an intermediate node in ids_from path is an Array (regression: Run #60 TypeError)' do
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result.results", "output" => "emails" } ]
      end
      let(:array_result_input) { { "emails" => emails, "result" => filter_result } }

      it 'returns empty emails instead of raising TypeError' do
        result = call(array_result_input, operations:)
        expect(result["emails"]).to eq([])
      end
    end

    context 'when renaming a key' do
      let(:operations) { [ { "type" => "rename", "from" => "emails", "to" => "messages" } ] }

      it 'renames the key' do
        result = call(input, operations:)
        expect(result).to have_key("messages")
        expect(result).not_to have_key("emails")
      end
    end

    context 'when picking keys' do
      let(:operations) { [ { "type" => "pick", "keys" => [ "emails" ] } ] }

      it 'keeps only the specified keys' do
        result = call(input, operations:)
        expect(result.keys).to eq([ "emails" ])
      end
    end

    context 'with sequential operations (filter_by_ids then pick)' do
      let(:operations) do
        [
          { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" },
          { "type" => "pick", "keys" => [ "emails" ] }
        ]
      end

      it 'applies operations in order and returns only filtered emails' do
        result = call(input, operations:)
        expect(result.keys).to eq([ "emails" ])
        expect(result["emails"].map { _1["id"] }).to eq(%w[e1 e3])
      end
    end

    context 'when no operations are provided' do
      it 'returns the input unchanged' do
        result = call(input)
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
      let(:operations) do
        [ { "type" => "merge_by_index", "source" => "emails", "ids" => "stored_ids", "inject" => "id", "output" => "records" } ]
      end

      it 'zips source objects with ids, injecting the id field into each object' do
        result = call(merge_input, operations:)
        expect(result["records"]).to eq([
          { "id" => 986, "email_id" => "19d4", "company" => "Bilendo" },
          { "id" => 987, "email_id" => "abcd", "company" => "Foo" }
        ])
      end

      it 'truncates to the shorter array when source is longer than ids' do
        long_source = merge_input["emails"] + [ { "email_id" => "extra", "company" => "Extra" } ]
        result = call({ "emails" => long_source, "stored_ids" => merge_input["stored_ids"] }, operations:)
        expect(result["records"].length).to eq(2)
        expect(result["records"].map { _1["id"] }).to eq([ 986, 987 ])
      end

      it 'truncates to the shorter array when ids is longer than source' do
        long_ids = merge_input["stored_ids"] + [ 999 ]
        result = call({ "emails" => merge_input["emails"], "stored_ids" => long_ids }, operations:)
        expect(result["records"].length).to eq(2)
        expect(result["records"].map { _1["id"] }).to eq([ 986, 987 ])
      end

      it 'returns empty records when source is nil' do
        result = call({ "emails" => nil, "stored_ids" => merge_input["stored_ids"] }, operations:)
        expect(result["records"]).to eq([])
      end

      it 'returns empty records when ids is nil' do
        result = call({ "emails" => merge_input["emails"], "stored_ids" => nil }, operations:)
        expect(result["records"]).to eq([])
      end
    end

    context 'when an unknown operation type is given' do
      it 'raises ArgumentError with the unknown type' do
        expect { call(input, operations: [ { "type" => "explode" } ]) }
          .to raise_error(ArgumentError, /unknown operation type: explode/)
      end
    end

    context 'when filter_by_ids yields no matches' do
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" } ]
      end

      it 'returns an empty array for the output key' do
        result = call({ "emails" => emails, "result" => [] }, operations:)
        expect(result["emails"]).to eq([])
      end
    end

    context 'when source items have no id key' do
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" } ]
      end
      let(:emails_without_id) { [ { "subject" => "A" }, { "subject" => "B" } ] }

      it 'excludes items with no id from the filtered output' do
        result = call({ "emails" => emails_without_id, "result" => [] }, operations:)
        expect(result["emails"]).to eq([])
      end
    end

    context 'when ids_from contains non-Hash items' do
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result", "output" => "emails" } ]
      end

      it 'ignores non-Hash items in ids_from when building the allowed set' do
        result = call({ "emails" => emails, "result" => [ "e1", "e3" ] }, operations:)
        expect(result["emails"]).to eq([])
      end
    end

    context 'when merge_by_index op keys are non-string (Symbol)' do
      let(:merge_input) do
        {
          "emails"     => [ { "email_id" => "abc", "company" => "Acme" } ],
          "stored_ids" => [ 99 ]
        }
      end

      it 'coerces Symbol source key to string for lookup' do
        operations = [
          { "type" => "merge_by_index", "source" => :emails, "ids" => "stored_ids",
            "inject" => "id", "output" => "records" }
        ]
        result = call(merge_input, operations:)
        expect(result["records"]).to eq([ { "id" => 99, "email_id" => "abc", "company" => "Acme" } ])
      end

      it 'coerces Symbol inject key to string in the merged hash' do
        operations = [
          { "type" => "merge_by_index", "source" => "emails", "ids" => "stored_ids",
            "inject" => :id, "output" => "records" }
        ]
        result = call(merge_input, operations:)
        expect(result["records"].first).to have_key("id")
        expect(result["records"].first).not_to have_key(:id)
      end

      it 'coerces Symbol dest key to string' do
        operations = [
          { "type" => "merge_by_index", "source" => "emails", "ids" => "stored_ids",
            "inject" => "id", "output" => :records }
        ]
        result = call(merge_input, operations:)
        expect(result).to have_key("records")
        expect(result).not_to have_key(:records)
      end
    end

    context 'when rename op keys are non-string (Symbol)' do
      it 'coerces Symbol from key to string before comparing' do
        operations = [ { "type" => "rename", "from" => :emails, "to" => "messages" } ]
        result = call(input, operations:)
        expect(result).to have_key("messages")
        expect(result).not_to have_key("emails")
      end

      it 'coerces Symbol to key to string in the output' do
        operations = [ { "type" => "rename", "from" => "emails", "to" => :messages } ]
        result = call(input, operations:)
        expect(result).to have_key("messages")
        expect(result).not_to have_key(:messages)
      end
    end

    context 'when dig_path has a nil intermediate node' do
      let(:operations) do
        [ { "type" => "filter_by_ids", "source" => "emails", "ids_from" => "result.ids", "output" => "emails" } ]
      end

      it 'returns empty when an intermediate path segment is nil' do
        result = call({ "emails" => emails, "result" => nil }, operations:)
        expect(result["emails"]).to eq([])
      end
    end

    describe '.input_schema' do
      it 'declares operations as an optional array' do
        schema = described_class.input_schema
        expect(schema["type"]).to eq("object")
        expect(schema["properties"]["operations"]["type"]).to eq("array")
        expect(schema["required"]).to be_nil
      end
    end
  end
end
