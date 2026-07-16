
require 'rails_helper'

RSpec.describe Pipeline::EmailProviderFetcher do
  subject(:fetcher) { described_class.new(date: date) }

  let(:date) { Date.new(2026, 3, 15) }
  let(:tmp_file) { Rails.root.join('tmp', "emails_#{date - 1}_#{date}.json") }

  after { FileUtils.rm_f(tmp_file) }

  describe '#call' do
    context 'when a cache file already exists' do
      before { tmp_file.write([ { 'id' => 'cached1' } ].to_json) }

      it 'returns the cached emails without fetching from providers' do
        allow(Emails::RetrievalService).to receive(:call)

        result = fetcher.call

        expect(result).to eq([ { 'id' => 'cached1' } ])
        expect(Emails::RetrievalService).not_to have_received(:call)
      end
    end

    context 'when no cache file exists' do
      before do
        allow(Emails::RetrievalService).to receive(:call).and_return([])
      end

      it 'fetches from both gmail and yahoo with the correct date range' do
        fetcher.call

        expect(Emails::RetrievalService).to have_received(:call)
          .with(provider: 'gmail', after_date: date - 1, before_date: date)
        expect(Emails::RetrievalService).to have_received(:call)
          .with(provider: 'yahoo', after_date: date - 1, before_date: date)
      end

      it 'writes the fetched emails to the cache file' do
        allow(Emails::RetrievalService).to receive(:call).and_return([ { 'id' => 'msg1' } ])

        fetcher.call

        expect(JSON.parse(tmp_file.read)).to eq([ { 'id' => 'msg1' }, { 'id' => 'msg1' } ])
      end

      it 'keeps hash results from an Array-shaped provider response' do
        allow(Emails::RetrievalService).to receive(:call).and_return([ { 'id' => 'a' }, 'not_a_hash' ])

        result = fetcher.call

        expect(result).to eq([ { 'id' => 'a' }, { 'id' => 'a' } ])
      end

      it 'extracts results from a Hash-shaped provider response' do
        allow(Emails::RetrievalService).to receive(:call).and_return({ 'results' => [ { 'id' => 'b' } ] })

        result = fetcher.call

        expect(result).to eq([ { 'id' => 'b' }, { 'id' => 'b' } ])
      end

      it 'returns an empty array for an unrecognized provider response shape' do
        allow(Emails::RetrievalService).to receive(:call).and_return(nil)

        expect(fetcher.call).to eq([])
      end
    end
  end
end
