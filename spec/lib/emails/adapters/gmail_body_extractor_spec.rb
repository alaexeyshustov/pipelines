require 'rails_helper'

RSpec.describe Emails::Adapters::GmailBodyExtractor do
  def make_body(data)
    instance_double(Google::Apis::GmailV1::MessagePartBody, data: data)
  end

  def make_part(mime_type:, data: nil, parts: nil)
    instance_double(Google::Apis::GmailV1::MessagePart,
      mime_type: mime_type,
      body:      make_body(data),
      parts:     parts
    )
  end

  def make_payload(parts: nil, data: nil)
    instance_double(Google::Apis::GmailV1::MessagePart,
      parts: parts,
      body:  make_body(data)
    )
  end

  subject(:extractor) { described_class.new(payload) }

  describe '#body' do
    context 'when payload has no parts (simple message)' do
      let(:payload) { make_payload(data: 'Thank you for applying') }

      it 'returns the body data' do
        expect(extractor.body).to eq('Thank you for applying')
      end
    end

    context 'when payload has empty body and no parts' do
      let(:payload) { make_payload(data: '') }

      it 'returns an empty string' do
        expect(extractor.body).to eq('')
      end
    end

    context 'when payload is multipart with text/plain and text/html' do
      let(:plain_part) { make_part(mime_type: 'text/plain', data: 'Plain text body') }
      let(:html_part)  { make_part(mime_type: 'text/html',  data: '<b>HTML body</b>') }
      let(:payload)    { make_payload(parts: [ plain_part, html_part ]) }

      it 'prefers text/plain over text/html' do
        expect(extractor.body).to eq('Plain text body')
      end
    end

    context 'when payload is multipart with only text/html' do
      let(:html_part) { make_part(mime_type: 'text/html', data: '<b>HTML body</b>') }
      let(:payload)   { make_payload(parts: [ html_part ]) }

      it 'returns the HTML body' do
        expect(extractor.body).to eq('<b>HTML body</b>')
      end
    end

    context 'when payload is multipart with multiple text/plain parts' do
      let(:first_part)  { make_part(mime_type: 'text/plain', data: 'First part') }
      let(:second_part) { make_part(mime_type: 'text/plain', data: 'Second part') }
      let(:payload)     { make_payload(parts: [ first_part, second_part ]) }

      it 'joins all text/plain parts with double newlines' do
        expect(extractor.body).to eq("First part\n\nSecond part")
      end
    end

    context 'when payload is nested multipart (multipart/alternative inside multipart/mixed)' do
      let(:inner_plain) { make_part(mime_type: 'text/plain', data: 'Nested plain') }
      let(:inner_html)  { make_part(mime_type: 'text/html',  data: '<p>Nested HTML</p>') }
      let(:inner_multipart) do
        instance_double(Google::Apis::GmailV1::MessagePart,
          mime_type: 'multipart/alternative',
          body:      make_body(nil),
          parts:     [ inner_plain, inner_html ]
        )
      end
      let(:payload) { make_payload(parts: [ inner_multipart ]) }

      it 'recursively finds text/plain in nested parts' do
        expect(extractor.body).to eq('Nested plain')
      end
    end

    context 'when multipart payload has only non-text parts' do
      let(:attachment) do
        instance_double(Google::Apis::GmailV1::MessagePart,
          mime_type: 'application/pdf',
          body:      make_body(nil),
          parts:     nil
        )
      end
      let(:payload) { make_payload(parts: [ attachment ]) }

      it 'returns an empty string' do
        expect(extractor.body).to eq('')
      end
    end
  end
end
