require 'rails_helper'

RSpec.describe Emails::FetchExecutor do
  describe '.call' do
    it 'calls Emails.list_messages for both gmail and yahoo' do
      date = Date.today
      input = { "date" => date.to_s }

      allow(Emails).to receive(:list_messages).with('gmail', after_date: date - 1, before_date: date).and_return([ { id: 1 } ])
      allow(Emails).to receive(:list_messages).with('yahoo', after_date: date - 1, before_date: date).and_return([ { id: 2 } ])

      result = described_class.call(input)
      expect(result).to eq({ "emails" => [ { id: 1 }, { id: 2 } ] })
    end

    it 'uses today as default date' do
      date = Date.today
      allow(Emails).to receive(:list_messages).and_return([])

      described_class.call({})

      expect(Emails).to have_received(:list_messages).with('gmail', after_date: date - 1, before_date: date)
      expect(Emails).to have_received(:list_messages).with('yahoo', after_date: date - 1, before_date: date)
    end
  end
end
