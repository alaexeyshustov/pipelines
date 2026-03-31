require 'rails_helper'

RSpec.describe Emails::Adapters::ImapBodyParser do
  def make_part(mime_type:, decoded: '', multipart: false, parts: [])
    double('part',
      mime_type:  mime_type,
      multipart?: multipart,
      parts:      parts,
      decoded:    decoded
    )
  end

  describe '.decode_header' do
    it 'returns the value as a UTF-8 string' do
      expect(described_class.decode_header('Hello World')).to eq('Hello World')
    end

    it 'returns nil when value is nil' do
      expect(described_class.decode_header(nil)).to be_nil
    end

    it 'converts non-string values via to_s' do
      expect(described_class.decode_header(42)).to eq('42')
    end

    it 'replaces invalid bytes and returns a UTF-8 string' do
      binary = "caf\xE9".b
      result = described_class.decode_header(binary)
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::UTF_8)
    end
  end

  describe '#body' do
    subject(:parser) { described_class.new(mail) }

    context 'when mail is a simple text/plain message' do
      let(:mail) do
        double('mail', multipart?: false, mime_type: 'text/plain', decoded: 'Plain text content')
      end

      it 'returns the decoded plain text' do
        expect(parser.body).to eq('Plain text content')
      end
    end

    context 'when mail is a simple text/html message' do
      let(:mail) do
        double('mail', multipart?: false, mime_type: 'text/html', decoded: '<p>Hello <b>World</b></p>')
      end

      it 'strips HTML tags' do
        expect(parser.body).to eq('Hello World')
      end
    end

    context 'when mail is multipart with text/plain and text/html' do
      let(:plain_part) { make_part(mime_type: 'text/plain', decoded: 'Plain text') }
      let(:html_part)  { make_part(mime_type: 'text/html',  decoded: '<b>HTML</b>') }
      let(:mail)       { double('mail', multipart?: true, parts: [ plain_part, html_part ]) }

      it 'prefers text/plain over text/html' do
        expect(parser.body).to eq('Plain text')
      end
    end

    context 'when mail is multipart with only text/html' do
      let(:html_part) { make_part(mime_type: 'text/html', decoded: '<p>HTML only</p>') }
      let(:mail)      { double('mail', multipart?: true, parts: [ html_part ]) }

      it 'returns the body with HTML tags stripped' do
        expect(parser.body).to eq('HTML only')
      end
    end

    context 'when mail is multipart with no text parts (recursive fallback)' do
      let(:nested_plain) { make_part(mime_type: 'text/plain', decoded: 'Nested content') }
      let(:nested_part)  { make_part(mime_type: 'multipart/alternative', multipart: true, parts: [ nested_plain ]) }
      let(:mail)         { double('mail', multipart?: true, parts: [ nested_part ]) }

      it 'recursively extracts body from nested parts' do
        expect(parser.body).to eq('Nested content')
      end
    end

    context 'when mail is multipart with only non-text attachments' do
      let(:attachment) { make_part(mime_type: 'application/pdf', decoded: '') }
      let(:mail)       { double('mail', multipart?: true, parts: [ attachment ]) }

      it 'returns an empty string' do
        expect(parser.body).to eq('')
      end
    end
  end
end
