require 'rails_helper'

RSpec.describe Emails::FetchExecutor do
  describe '.call' do
    let(:date) { Date.today }

    before do
      allow(Emails).to receive(:list_messages).and_return([])
    end

    it 'calls Emails.list_messages for each provider' do
      allow(Emails).to receive(:list_messages).with('gmail', any_args).and_return([ { id: 1 } ])
      allow(Emails).to receive(:list_messages).with('yahoo', any_args).and_return([ { id: 2 } ])

      result = described_class.call(date: date.to_s, providers: %w[gmail yahoo])
      expect(result).to eq({ "emails" => [ { id: 1 }, { id: 2 } ] })
    end

    it 'uses today as default date when not provided' do
      described_class.call

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(after_date: date - 1, before_date: date))
      expect(Emails).to have_received(:list_messages).with('yahoo', hash_including(after_date: date - 1, before_date: date))
    end

    it 'falls back to today when date is nil' do
      described_class.call(date: nil)

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(after_date: date - 1, before_date: date))
    end

    it 'passes max_results to list_messages' do
      described_class.call(date: date.to_s, max_results: 5)

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(max_results: 5))
      expect(Emails).to have_received(:list_messages).with('yahoo', hash_including(max_results: 5))
    end

    it 'defaults to 10 max_results' do
      described_class.call(date: date.to_s)

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(max_results: 10))
    end

    describe '.input_schema' do
      it 'returns a valid JSON Schema object' do
        schema = described_class.input_schema
        expect(schema["type"]).to eq("object")
        expect(schema["properties"].keys).to include("date", "providers", "max_results")
      end

      it 'has no required fields (all have defaults)' do
        expect(described_class.input_schema["required"]).to be_nil
      end
    end
  end
end
