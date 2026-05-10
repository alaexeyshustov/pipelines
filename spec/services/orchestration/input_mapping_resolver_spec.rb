require 'rails_helper'

RSpec.describe Orchestration::InputMappingResolver do
  subject(:resolver) { described_class.new(input_mapping: input_mapping, previous_outputs: previous_outputs) }

  let(:previous_outputs) do
    {
      "fetch" => { "emails" => [ { "id" => "e1", "subject" => "Hello" } ] }
    }
  end

  describe '#resolve' do
    context 'with an empty input_mapping' do
      let(:input_mapping) { {} }

      it 'returns an empty hash' do
        expect(resolver.resolve).to eq({})
      end
    end

    context 'with a required path that exists' do
      let(:input_mapping) do
        { "subject" => { "from" => "fetch", "path" => "emails" } }
      end

      it 'returns the resolved value at the path' do
        expect(resolver.resolve["subject"]).to eq([ { "id" => "e1", "subject" => "Hello" } ])
      end
    end

    context 'with an unknown from key' do
      let(:input_mapping) do
        { "data" => { "from" => "nonexistent", "path" => "emails" } }
      end

      it 'raises UnknownOutputKey naming the from value' do
        expect { resolver.resolve }
          .to raise_error(described_class::UnknownOutputKey, /nonexistent/)
      end
    end

    context 'with a required path that does not exist' do
      let(:input_mapping) do
        { "missing" => { "from" => "fetch", "path" => "no_such_key" } }
      end

      it 'raises MissingPath naming the from and path' do
        expect { resolver.resolve }
          .to raise_error(described_class::MissingPath, /fetch.*no_such_key|no_such_key.*fetch/)
      end
    end

    context 'with optional: true and a missing path' do
      let(:input_mapping) do
        { "maybe" => { "from" => "fetch", "path" => "no_such_key", "optional" => true } }
      end

      it 'returns nil without raising' do
        expect { resolver.resolve }.not_to raise_error
        expect(resolver.resolve["maybe"]).to be_nil
      end
    end

    context 'with a whole-output reference (no path)' do
      let(:input_mapping) do
        { "all_fetch" => { "from" => "fetch" } }
      end

      it 'returns the entire upstream output hash' do
        expect(resolver.resolve["all_fetch"]).to eq(
          { "emails" => [ { "id" => "e1", "subject" => "Hello" } ] }
        )
      end
    end

    context 'with a deep dot path' do
      let(:previous_outputs) do
        { "store" => { "result" => { "ids" => [ 1, 2, 3 ] } } }
      end

      let(:input_mapping) do
        { "stored_ids" => { "from" => "store", "path" => "result.ids" } }
      end

      it 'digs into nested output keys' do
        expect(resolver.resolve["stored_ids"]).to eq([ 1, 2, 3 ])
      end
    end

    context 'with a numeric path segment into an array' do
      let(:input_mapping) do
        { "first_subject" => { "from" => "fetch", "path" => "emails.0.subject" } }
      end

      it 'coerces the numeric segment to an integer and returns the element' do
        expect(resolver.resolve["first_subject"]).to eq("Hello")
      end
    end

    context 'with a non-numeric string segment against an Array node' do
      let(:input_mapping) do
        { "bad" => { "from" => "fetch", "path" => "emails.subject" } }
      end

      it 'raises MissingPath rather than silently coercing the segment to 0' do
        expect { resolver.resolve }
          .to raise_error(described_class::MissingPath, /emails\.subject/)
      end
    end

    context 'with a non-numeric string segment against an Array node and optional: true' do
      let(:input_mapping) do
        { "bad" => { "from" => "fetch", "path" => "emails.subject", "optional" => true } }
      end

      it 'returns nil without raising' do
        expect(resolver.resolve["bad"]).to be_nil
      end
    end

    context 'with the reserved _initial slot' do
      let(:previous_outputs) do
        {
          "_initial"  => { "date" => "2026-05-10", "providers" => [ "gmail" ] },
          "fetch"     => { "emails" => [ { "id" => "e1", "subject" => "Hello" } ] }
        }
      end

      let(:input_mapping) do
        { "run_date" => { "from" => "_initial", "path" => "date" } }
      end

      it 'resolves the _initial slot like any other output key' do
        expect(resolver.resolve["run_date"]).to eq("2026-05-10")
      end
    end
  end
end
