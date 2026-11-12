require 'rails_helper'

RSpec.describe Emails::Adapters::ImapBodyParser do
  def make_part(mime_type:, decoded: '', multipart: false, parts: [])
    if multipart
      part = Mail::Part.new
      part.content_type = "#{mime_type}; boundary=----=_Part_test"
      parts.each { |sub| part.add_part(sub) }
      part
    else
      Mail::Part.new("Content-Type: #{mime_type}\r\n\r\n#{decoded}")
    end
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
      let(:mail) { Mail.new("Content-Type: text/plain\r\n\r\nPlain text content") }

      it 'returns the decoded plain text' do
        expect(parser.body).to eq('Plain text content')
      end
    end

    context 'when mail is a simple text/html message' do
      let(:mail) { Mail.new("Content-Type: text/html\r\n\r\n<p>Hello <b>World</b></p>") }

      it 'strips HTML tags' do
        expect(parser.body).to eq('Hello World')
      end
    end

    context 'when an HTML-only mail has a style block' do
      let(:mail) { Mail.new("Content-Type: text/html\r\n\r\n<style>p { color: red; }</style><p>Hello</p>") }

      it 'returns the text without CSS' do
        expect(parser.body).to eq('Hello')
      end
    end

    context 'when mail is multipart with text/plain and text/html' do
      let(:plain_part) { make_part(mime_type: 'text/plain', decoded: 'Plain text') }
      let(:html_part)  { make_part(mime_type: 'text/html',  decoded: '<b>HTML</b>') }
      let(:mail) do
        m = Mail.new
        m.content_type = "multipart/alternative; boundary=----=_Msg_test"
        m.add_part(plain_part)
        m.add_part(html_part)
        m
      end

      it 'prefers text/plain over text/html' do
        expect(parser.body).to eq('Plain text')
      end
    end

    context 'when mail is multipart with only text/html' do
      let(:html_part) { make_part(mime_type: 'text/html', decoded: '<p>HTML only</p>') }
      let(:mail) do
        m = Mail.new
        m.content_type = "multipart/alternative; boundary=----=_Msg_test"
        m.add_part(html_part)
        m
      end

      it 'returns the body with HTML tags stripped' do
        expect(parser.body).to eq('HTML only')
      end
    end

    context 'when mail is multipart with no text parts (recursive fallback)' do
      let(:nested_plain) { make_part(mime_type: 'text/plain', decoded: 'Nested content') }
      let(:nested_part)  { make_part(mime_type: 'multipart/alternative', multipart: true, parts: [ nested_plain ]) }
      let(:mail) do
        m = Mail.new
        m.content_type = "multipart/mixed; boundary=----=_Msg_test"
        m.add_part(nested_part)
        m
      end

      it 'recursively extracts body from nested parts' do
        expect(parser.body).to eq('Nested content')
      end
    end

    context 'when mail is multipart with only non-text attachments' do
      let(:attachment) { make_part(mime_type: 'application/pdf', decoded: '') }
      let(:mail) do
        m = Mail.new
        m.content_type = "multipart/mixed; boundary=----=_Msg_test"
        m.add_part(attachment)
        m
      end

      it 'returns an empty string' do
        expect(parser.body).to eq('')
      end
    end

    context 'when mail is multipart/mixed with multipart/alternative and a PDF attachment' do
      let(:mail) do
        Mail.new(<<~EML.gsub("\n", "\r\n"))
          From: a@example.com
          To: b@example.com
          Subject: Offer
          MIME-Version: 1.0
          Content-Type: multipart/mixed; boundary="outer"

          --outer
          Content-Type: multipart/alternative; boundary="inner"

          --inner
          Content-Type: text/plain; charset=UTF-8

          Hello plain
          --inner
          Content-Type: text/html; charset=UTF-8

          <p>Hello html</p>
          --inner--

          --outer
          Content-Type: application/pdf; name="offer.pdf"
          Content-Disposition: attachment; filename="offer.pdf"
          Content-Transfer-Encoding: 7bit

          %PDF-1.4 raw pdf bytes
          --outer--
        EML
      end

      it 'returns only the text of the readable part' do
        expect(parser.body).to eq('Hello plain')
      end
    end

    context 'when the only text part is an attachment' do
      let(:mail) do
        Mail.new(<<~EML.gsub("\n", "\r\n"))
          Content-Type: multipart/mixed; boundary="outer"

          --outer
          Content-Type: text/plain; name="notes.txt"
          Content-Disposition: attachment; filename="notes.txt"

          attached notes
          --outer--
        EML
      end

      it 'does not use it as the body' do
        expect(parser.body).to eq('')
      end
    end

    context 'when a single non-text message has a PDF body' do
      let(:mail) { Mail.new("Content-Type: application/pdf\r\n\r\n%PDF-1.4 bytes") }

      it 'returns an empty string' do
        expect(parser.body).to eq('')
      end
    end

    context 'when text/html sits in a nested multipart next to an attachment' do
      let(:mail) do
        Mail.new(<<~EML.gsub("\n", "\r\n"))
          Content-Type: multipart/mixed; boundary="outer"

          --outer
          Content-Type: multipart/related; boundary="rel"

          --rel
          Content-Type: text/html

          <p>Only html</p>
          --rel--

          --outer
          Content-Type: application/pdf
          Content-Disposition: attachment; filename="a.pdf"

          %PDF raw
          --outer--
        EML
      end

      it 'strips the html and ignores the attachment' do
        expect(parser.body).to eq('Only html')
      end
    end
  end

  describe '#html' do
    subject(:parser) { described_class.new(mail) }

    context 'when the message has an html body' do
      let(:mail) { Mail.new("Content-Type: text/html\r\n\r\n<p>Hello</p>") }

      it 'returns it as is' do
        expect(parser.html).to eq('<p>Hello</p>')
      end
    end

    context 'when the only text/html part is an attachment' do
      let(:mail) do
        Mail.new(<<~EML.gsub("\n", "\r\n"))
          Content-Type: multipart/mixed; boundary="outer"

          --outer
          Content-Type: text/plain

          See the attached page.
          --outer
          Content-Type: text/html
          Content-Disposition: attachment; filename="page.html"

          <p>Attached page</p>
          --outer--
        EML
      end

      it 'returns nil' do
        expect(parser.html).to be_nil
      end
    end

    context 'when an html body sits next to an html attachment' do
      let(:mail) do
        Mail.new(<<~EML.gsub("\n", "\r\n"))
          Content-Type: multipart/mixed; boundary="outer"

          --outer
          Content-Type: text/html
          Content-Disposition: attachment; filename="page.html"

          <p>Attached page</p>
          --outer
          Content-Type: text/html

          <p>Body</p>
          --outer--
        EML
      end

      it 'returns the body, not the attachment' do
        expect(parser.html).to eq('<p>Body</p>')
      end
    end
  end
end
