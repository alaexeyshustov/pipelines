require 'rails_helper'

RSpec.describe Emails::FetchExecutor do
  describe '.call' do
    let(:date) { Date.today }

    before do
      allow(Emails).to receive(:list_messages).and_return([])
    end

    it 'calls Emails.list_messages for both gmail and yahoo' do
      allow(Emails).to receive(:list_messages).with('gmail', any_args).and_return([ { id: 1 } ])
      allow(Emails).to receive(:list_messages).with('yahoo', any_args).and_return([ { id: 2 } ])

      result = described_class.call({ "date" => date.to_s })
      expect(result).to eq({ "emails" => [ { id: 1 }, { id: 2 } ] })
    end

    it 'uses today as default date' do
      described_class.call({})

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(after_date: date - 1, before_date: date))
      expect(Emails).to have_received(:list_messages).with('yahoo', hash_including(after_date: date - 1, before_date: date))
    end

    it 'passes max_results from params to list_messages' do
      described_class.call({ "date" => date.to_s }, { "max_results" => 5 })

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(max_results: 5))
      expect(Emails).to have_received(:list_messages).with('yahoo', hash_including(max_results: 5))
    end

    it 'defaults to 10 max_results when not specified' do
      described_class.call({ "date" => date.to_s })

      expect(Emails).to have_received(:list_messages).with('gmail', hash_including(max_results: 10))
    end
  end
end
