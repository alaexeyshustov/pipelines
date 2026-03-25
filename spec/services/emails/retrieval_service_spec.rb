require 'rails_helper'

RSpec.describe Emails::RetrievalService do
  subject(:service) { described_class.new(provider: 'gmail', after_date: '2026-01-01', before_date: '2026-01-02') }

  let(:email_fixture) do
    ->(id) { { id: id, subject: "Job offer #{id}", from: "hr@example.com", date: "Mon, 1 Jan 2026 12:00:00 +0000" } }
  end

  before do
    allow(Emails).to receive(:list_messages).and_return([])
  end

  describe '#call' do
    it 'calls Emails.list_messages with the correct params' do
      service.call

      expect(Emails).to have_received(:list_messages).with(
        'gmail',
        max_results:  100,
        after_date:   Date.parse('2026-01-01'),
        before_date:  Date.parse('2026-01-02'),
        offset:       0
      )
    end

    it 'returns an array of normalized email hashes' do
      allow(Emails).to receive(:list_messages).and_return([ email_fixture.call('msg1') ])

      result = service.call

      expect(result).to eq([
        { 'id' => 'msg1', 'subject' => 'Job offer msg1', 'provider' => 'gmail',
          'date' => 'Mon, 1 Jan 2026 12:00:00 +0000', 'from' => 'hr@example.com' }
      ])
    end

    it 'paginates when a full page of 100 is returned' do
      page1 = Array.new(100) { |i| email_fixture.call("msg#{i}") }
      page2 = [ email_fixture.call('msg100') ]

      allow(Emails).to receive(:list_messages).with('gmail', hash_including(offset: 0)).and_return(page1)
      allow(Emails).to receive(:list_messages).with('gmail', hash_including(offset: 100)).and_return(page2)

      result = service.call

      expect(result.size).to eq(101)
      expect(Emails).to have_received(:list_messages).twice
    end

    it 'stops paginating when fewer than 100 emails are returned' do
      allow(Emails).to receive(:list_messages).and_return(Array.new(99) { |i| email_fixture.call("msg#{i}") })

      service.call

      expect(Emails).to have_received(:list_messages).once
    end

    it 'returns an empty array when no emails are found' do
      expect(service.call).to eq([])
    end
  end
end
