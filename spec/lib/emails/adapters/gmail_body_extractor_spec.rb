require 'rails_helper'

RSpec.describe Emails::Adapters::GmailBodyExtractor do
  def make_body(data)
    Google::Apis::GmailV1::MessagePartBody.new(data: data)
  end

  def make_part(mime_type:, data: nil, parts: nil, charset: nil)
    headers = charset ? [ Google::Apis::GmailV1::MessagePartHeader.new(name: 'Content-Type', value: "#{mime_type}; charset=\"#{charset}\"") ] : nil
    Google::Apis::GmailV1::MessagePart.new(
      mime_type: mime_type,
      body:      make_body(data),
      parts:     parts,
      headers:   headers
    )
  end

  def make_payload(parts: nil, data: nil, mime_type: nil)
    Google::Apis::GmailV1::MessagePart.new(
      mime_type: mime_type,
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

    context 'when payload is a single text/html part' do
      let(:payload) { make_payload(mime_type: 'text/html', data: '<p>Hello <b>there</b></p>') }

      it 'returns the HTML stripped to plain text' do
        expect(extractor.body).to eq('Hello there')
      end

      it 'keeps the raw HTML in #html' do
        expect(extractor.html).to eq('<p>Hello <b>there</b></p>')
      end
    end

    context 'when an HTML-only payload has a style block and entities' do
      let(:payload) do
        make_payload(mime_type: 'text/html',
                     data: '<style>p { color: red; }</style><p>Fish &amp; chips</p><p>Second line</p>')
      end

      it 'returns the text without CSS, with entities decoded' do
        expect(extractor.body).to eq("Fish & chips\nSecond line")
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

      it 'returns the HTML stripped to plain text' do
        expect(extractor.body).to eq('HTML body')
      end

      it 'keeps the raw HTML in #html' do
        expect(extractor.html).to eq('<b>HTML body</b>')
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
        Google::Apis::GmailV1::MessagePart.new(
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
        Google::Apis::GmailV1::MessagePart.new(
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

  describe 'non-ASCII content (Gmail returns body.data as ASCII-8BIT)' do
    let(:text) { 'Привет München €' }

    it 'keeps UTF-8 text when the part declares no charset' do
      payload = make_part(mime_type: 'text/plain', data: text.b)
      expect(described_class.new(payload).body).to eq(text)
    end

    it 'keeps UTF-8 html in #html and in the stripped #body' do
      payload = make_part(mime_type: 'text/html', data: "<p>#{text}</p>".b, charset: 'UTF-8')
      extractor = described_class.new(payload)
      expect([ extractor.html, extractor.body ]).to eq([ "<p>#{text}</p>", text ])
    end

    it 'transcodes the declared charset to UTF-8' do
      payload = make_part(mime_type: 'text/plain', data: 'München'.encode('ISO-8859-1').b, charset: 'ISO-8859-1')
      expect(described_class.new(payload).body).to eq('München')
    end

    it 'scrubs invalid bytes and falls back to UTF-8 for an unknown charset' do
      payload = make_part(mime_type: 'text/plain', data: "caf\xE9 ok".b, charset: 'no-such-charset')
      body = described_class.new(payload).body
      expect([ body.encoding, body.valid_encoding?, body ]).to eq([ Encoding::UTF_8, true, "caf\uFFFD ok" ])
    end

    it 'decodes parts of a multipart message' do
      plain = make_part(mime_type: 'text/plain', data: text.b)
      payload = make_payload(parts: [ plain ], mime_type: 'multipart/alternative')
      expect(described_class.new(payload).body).to eq(text)
    end
  end
end
