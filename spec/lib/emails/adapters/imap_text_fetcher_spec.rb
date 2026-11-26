require "rails_helper"

RSpec.describe Emails::Adapters::ImapTextFetcher do
  include ImapResponseHelpers

  subject(:fetcher) { described_class.new(session) }

  let(:session) { Emails::Adapters::ImapSession.new(host: "imap.mail.yahoo.com", port: 993, username: "me@yahoo.com", password: "secret") }
  let(:calls) { [] }
  let(:imap) { Net::IMAP.allocate }
  let(:part_limit) { "BODY.PEEK[%<path>s]<0.1048576>" }

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(login: nil, select: nil)
  end


  def fetch_mail(message, uid: 101)
    stub_imap_message(imap, message, uid: uid, calls: calls)
    fetcher.mail(uid, mailbox: "INBOX")
  end

  def body_fetches = calls.drop(1)

  def parsed(mail) = Emails::Adapters::ImapBodyParser.new(mail)

  it "limits a text part to 1 MiB and a message to 20 text parts" do
    expect(described_class::MAX_TEXT_PART_BYTES).to eq(1_048_576)
    expect(described_class::MAX_TEXT_PARTS).to eq(20)
  end

  describe "#mail" do
    it "selects the mailbox and takes the session lock once around all IMAP calls" do
      allow(session).to receive(:with_lock).and_call_original
      fetch_mail(imap_fixture("mixed_pdf"))

      expect(imap).to have_received(:select).with("INBOX")
      expect(session).to have_received(:with_lock).once
    end

    it "asks for the structure and header first, without FLAGS" do
      fetch_mail(imap_fixture("mixed_pdf"))

      expect(calls.first).to include("BODYSTRUCTURE", "BODY.PEEK[HEADER]")
      expect(calls.first).not_to include("FLAGS")
    end

    context "with a 5 MB attachment declared in the structure" do
      let(:message) { imap_fixture("mixed_pdf", structure: "mixed_large_pdf") }

      it "fetches only the text part, with a partial range, and never the attachment" do
        mail = fetch_mail(message)

        expect(body_fetches).to eq([ [ format(part_limit, path: "1") ] ])
        expect(calls.flatten).not_to include("RFC822", "BODY[]", "BODY.PEEK[]", "BODY.PEEK[TEXT]", "BODY.PEEK[2]", "BODY.PEEK[2]<0.1048576>")
        expect(parsed(mail).body).to eq("Please find my CV attached.")
      end

      it "keeps the headers of the message" do
        mail = fetch_mail(message)

        expect(mail).to have_attributes(subject: "Application", from: [ "hr@company.com" ], to: [ "test@yahoo.com" ])
        expect(mail.date.to_time.utc).to eq(Time.utc(2026, 1, 1, 12))
      end
    end

    context "when the message is the same as Mail.new(raw) would read" do
      %w[plain alternative mixed_pdf nested qp_latin1 base64_utf8 inline_image rfc822].each do |name|
        it "gives the same body and html for the #{name} fixture" do
          message = imap_fixture(name)
          legacy = parsed(Mail.new(message.raw))

          fetched = parsed(fetch_mail(message))

          expect(fetched.body).to eq(legacy.body)
          expect(fetched.html).to eq(legacy.html)
        end
      end

      it "keeps subject, from, to and date of the multipart fixtures" do
        message = imap_fixture("alternative")
        legacy = Mail.new(message.raw)

        mail = fetch_mail(message)

        expect([ mail.subject, mail.from, mail.to, mail.date ]).to eq([ legacy.subject, legacy.from, legacy.to, legacy.date ])
      end
    end

    describe "charsets and transfer encodings" do
      it "decodes a quoted-printable ISO-8859-1 part to UTF-8 like Mail.new(raw)" do
        body = parsed(fetch_mail(imap_fixture("qp_latin1"))).body

        expect(body).to include("Grüße aus Köln", "Gespräch")
        expect(body.encoding).to eq(Encoding::UTF_8)
      end

      it "decodes a base64 UTF-8 part" do
        expect(parsed(fetch_mail(imap_fixture("base64_utf8"))).body).to eq("Привет, мир! Это тестовое письмо о вашей заявке.")
      end

      it "drops a charset that is not a plain token instead of copying it into a rebuilt part header" do
        message = imap_fixture("alternative")
        hostile = message.with(structure: message.structure.sub('"UTF-8"', '"utf-8; x-injected=1"'))
        plain = fetch_mail(hostile).parts.first

        expect(plain.header.to_s).not_to include("x-injected")
        expect(plain.content_type).to eq("text/plain")
        expect(plain.decoded).to eq(Mail.new(message.raw).text_part.decoded)
      end

      it "keeps a well-formed charset in a rebuilt part header" do
        expect(fetch_mail(imap_fixture("alternative")).parts.map(&:content_type)).to eq([ "text/plain; charset=UTF-8", "text/html; charset=UTF-8" ])
      end

      it "asks for the part of a single-part message with the path 1" do
        fetch_mail(imap_fixture("qp_latin1"))

        expect(body_fetches).to eq([ [ "BODY.PEEK[1]<0.1048576>" ] ])
      end
    end

    describe "a text part with a filename" do
      it "keeps the body of a single-part text/plain message that has a name parameter" do
        message = imap_fixture("named_plain")

        mail = fetch_mail(message)

        expect(body_fetches).to eq([ [ format(part_limit, path: "1") ] ])
        expect(parsed(mail).body).to eq(parsed(Mail.new(message.raw)).body)
        expect(parsed(mail).body).to eq("hello named")
      end

      it "does not fetch a text part of a multipart message that is an attachment" do
        message = imap_fixture("text_attachment")

        mail = fetch_mail(message)

        expect(body_fetches).to eq([ [ format(part_limit, path: "1") ] ])
        expect(parsed(mail).body).to eq("main body")
      end
    end

    describe "a server that answers a partial fetch without the <0> offset" do
      it "still reads the body from the BODY[1] key" do
        message = imap_fixture("plain")
        stub_imap_message(imap, message, uid: 101, calls: calls, offset_suffix: false)

        mail = fetcher.mail(101, mailbox: "INBOX")

        expect(parsed(mail).body).to eq(parsed(Mail.new(message.raw)).body)
        expect(parsed(mail).body).to include("application was successful")
      end
    end

    describe "a server that drops the blank line ending BODY[HEADER]" do
      it "keeps the body of a single-part message apart from the last header" do
        stub_const("HeaderWithoutBlankLine", Class.new(ImapResponseHelpers::Message) { def header = super.sub(/(?:\r\n)+\z/, "") })
        message = HeaderWithoutBlankLine.new(**imap_text_message("first body line\r\nsecond").to_h)

        mail = fetch_mail(message)

        expect(mail.header["Content-Transfer-Encoding"].to_s).to eq("7bit")
        expect(parsed(mail).body).to eq("first body line\nsecond")
      end

      it "drops a final Content-Type line and keeps the rebuilt multipart header apart from the original headers" do
        stub_const("HeaderWithoutBlankLine", Class.new(ImapResponseHelpers::Message) { def header = super.sub(/(?:\r\n)+\z/, "") })
        message = HeaderWithoutBlankLine.new(**imap_fixture("alternative").to_h)
        legacy = Mail.new(message.raw)

        mail = fetch_mail(message)

        expect(mail.header.to_s).not_to include("multipart/alternative")
        expect(mail.parts.map(&:mime_type)).to eq(%w[text/plain text/html])
        expect([ mail.message_id, parsed(mail).body ]).to eq([ legacy.message_id, parsed(legacy).body ])
      end
    end

    describe "a message expunged between the header and the body request" do
      it "returns nil instead of a Mail with an empty body" do
        message = imap_fixture("alternative")
        allow(imap).to receive(:uid_fetch) do |uid, attrs, *|
          calls << Array(attrs)
          calls.size == 1 ? [ imap_fetch_response(message, Array(attrs), uid: uid) ] : nil
        end

        expect(fetcher.mail(101, mailbox: "INBOX")).to be_nil
        expect(calls.size).to eq(2)
      end
    end

    describe "multipart messages" do
      it "fetches every text part of nested alternatives in one request and not the image or the PDF" do
        mail = fetch_mail(imap_fixture("nested"))

        expect(body_fetches).to eq([ %w[BODY.PEEK[1.1.1]<0.1048576> BODY.PEEK[1.1.2]<0.1048576>] ])
        expect(parsed(mail)).to have_attributes(body: "Nested plain text", html: "<p>Nested html</p>")
      end

      it "rebuilds a multipart message from the text parts only" do
        mail = fetch_mail(imap_fixture("nested"))

        expect(mail).to be_multipart
        expect(mail.parts.map(&:mime_type)).to eq(%w[text/plain text/html])
      end

      it "does not read text inside a message/rfc822 part" do
        fetch_mail(imap_fixture("rfc822"))

        expect(body_fetches).to eq([ [ "BODY.PEEK[1]<0.1048576>" ] ])
      end
    end

    describe "limits" do
      it "requests the 1 MiB range for a bigger text part and returns at most that much of it" do
        big = "#{'y' * 75}\r\n" * 20_000 # about 1.5 MB
        message = imap_text_message(big, subject: "Big")

        mail = fetch_mail(message)

        expect(body_fetches).to eq([ [ "BODY.PEEK[1]<0.1048576>" ] ])
        expect(mail.body.raw_source.bytesize).to be <= 1_048_576
        expect(parsed(mail).body.bytesize).to be_between(1_000_000, 1_048_576)
      end

      it "fetches only the first 20 of 25 text siblings" do
        fetch_mail(imap_siblings_message(25))

        expect(body_fetches).to eq([ (1..20).map { |n| "BODY.PEEK[#{n}]<0.1048576>" } ])
      end

      it "keeps the siblings in tree order" do
        mail = fetch_mail(imap_siblings_message(25))

        expect(parsed(mail).body.split("\n\n")).to eq((1..20).map { |n| "Sibling #{n}" })
      end

      it "does not raise for a structure nested 12 levels deep" do
        expect { fetch_mail(imap_nested_message(12)) }.not_to raise_error
      end

      it "fetches only the text parts within the depth cap of a structure nested 12 levels deep" do
        fetch_mail(imap_nested_message(12))

        fetched_paths = body_fetches.flatten.map { |attr| attr[/\[(.*)\]/, 1] }
        expect(fetched_paths).to include(nested_text_path(1), nested_text_path(5))
        expect(fetched_paths).not_to include(nested_text_path(11), nested_text_path(12))
      end

      it "returns a Mail with the text of the shallow levels only" do
        body = parsed(fetch_mail(imap_nested_message(12))).body

        expect(body).to include("level 1 text", "level 5 text")
        expect(body).not_to include("level 12 text")
      end
    end

    describe "a message without text parts" do
      it "sends only the first request and returns a header-only Mail" do
        mail = fetch_mail(imap_fixture("pdf_only"))

        expect(calls.size).to eq(1)
        expect(mail.subject).to eq("Scan")
        expect(parsed(mail).body).to eq("")
      end
    end

    it "returns nil when the UID does not exist" do
      stub_imap_message(imap, imap_fixture("plain"), uid: 101, calls: calls)

      expect(fetcher.mail(999, mailbox: "INBOX")).to be_nil
      expect(calls.size).to eq(1)
    end

    it "raises on a response it cannot parse instead of swallowing it" do
      allow(imap).to receive(:uid_fetch).and_raise(Net::IMAP::ResponseParseError, "bad structure")

      expect { fetcher.mail(101, mailbox: "INBOX") }.to raise_error(Net::IMAP::ResponseParseError)
    end
  end
end
