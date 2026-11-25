require "rails_helper"

RSpec.describe Emails::Adapters::YahooAdapter, "#attachments" do
  include ImapResponseHelpers

  subject(:adapter) { described_class.new(host: "imap.mail.yahoo.com", port: 993, username: "me@yahoo.com", password: "secret") }

  let(:imap) { Net::IMAP.allocate }
  let(:message) { imap_fixture("mixed_pdf") }
  let(:validity) { 77 }
  let!(:calls) { stub_imap_message(imap, message, uid: 101, validity: validity) }

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(login: nil, select: nil)
  end

  def listed_body_fetches = calls.flatten.grep(/\ABODY\.PEEK\[(?!HEADER)/)

  describe "listing" do
    it "lists a PDF as metadata keyed by its part path, with a lowercase type and the encoded size" do
      expect(adapter.attachments("77:101")).to eq(
        [ { id: "2", filename: "cv.pdf", mime_type: "application/pdf", size: message.bodystructure.parts.last.size } ]
      )
    end

    it "returns the same keys and types as the Gmail adapter" do
      listing = adapter.attachments("77:101").sole

      expect(listing).to match(id: a_kind_of(String), filename: a_kind_of(String), mime_type: a_kind_of(String), size: a_kind_of(Integer))
    end

    it "fetches no body part, only the structure" do
      adapter.attachments("77:101")

      expect(listed_body_fetches).to be_empty
      expect(calls.flatten).to include("BODYSTRUCTURE")
      expect(calls.flatten).not_to include("RFC822")
    end

    it "reports a large attachment by its declared size without downloading it" do
      stub_imap_message(imap, imap_fixture("mixed_pdf", structure: "mixed_large_pdf"), uid: 101, validity: validity)

      expect(adapter.attachments("77:101").sole).to include(size: 5_242_880)
    end

    it "lists a single-part PDF with the path 1" do
      stub_imap_message(imap, imap_fixture("pdf_only"), uid: 101, validity: validity)

      expect(adapter.attachments("77:101")).to match([ include(id: "1", filename: "scan.pdf", mime_type: "application/pdf") ])
    end

    it "leaves out inline images and the text parts" do
      stub_imap_message(imap, imap_fixture("inline_image"), uid: 101, validity: validity)

      expect(adapter.attachments("77:101")).to eq([])
    end

    it "leaves out attachments inside a message/rfc822 part" do
      stub_imap_message(imap, imap_fixture("rfc822"), uid: 101, validity: validity)

      ids = adapter.attachments("77:101").pluck(:id)

      expect(ids).to all(satisfy { |id| !id.start_with?("2.") })
    end

    it "lists the attachments of nested multipart messages, skipping the inline image" do
      stub_imap_message(imap, imap_fixture("nested"), uid: 101, validity: validity)

      expect(adapter.attachments("77:101")).to match([ include(id: "2", filename: "offer.pdf") ])
    end

    it "decodes RFC 2231 and RFC 2047 filenames" do
      stub_imap_message(imap, imap_fixture("encoded_filenames"), uid: 101, validity: validity)

      expect(adapter.attachments("77:101").map { |attachment| [ attachment[:id], attachment[:filename] ] }).to eq(
        [ [ "2", "Lebenslauf Müller.pdf" ], [ "3", "Zeugnis Grüße.pdf" ], [ "4", "CV Иван.pdf" ] ]
      )
    end

    it "accepts a legacy bare UID without comparing UIDVALIDITY" do
      expect(adapter.attachments("101")).to match([ include(id: "2") ])
      expect(imap).not_to have_received(:status)
    end

    it "returns an empty list for a message without attachments" do
      stub_imap_message(imap, imap_fixture("alternative"), uid: 101, validity: validity)

      expect(adapter.attachments("77:101")).to eq([])
    end

    it "raises when the message does not exist" do
      expect { adapter.attachments("77:999") }.to raise_error(/not found/i)
    end

    context "when UIDVALIDITY changed since the id was stored" do
      let(:validity) { 99 }

      it "raises before fetching the structure or any body, and not with a ThreadError" do
        expect { adapter.attachments("77:101") }.to raise_error(RuntimeError, /UIDVALIDITY changed/)

        expect(calls).to be_empty
      end
    end
  end

  describe "#attachment" do
    it "fetches only the requested part and returns its decoded bytes" do
      expect(adapter.attachment("77:101", "2")).to eq("%PDF-1.4\nfake cv bytes\n%%EOF\n")
      expect(listed_body_fetches).to eq([ "BODY.PEEK[2]" ])
    end

    it "does not fetch RFC822 or the text part" do
      adapter.attachment("77:101", "2")

      expect(calls.flatten).not_to include("RFC822", "BODY.PEEK[1]", "BODY.PEEK[1]<0.1048576>", "BODY.PEEK[TEXT]")
    end

    it "decodes the bytes by the transfer encoding of the part" do
      expect(adapter.attachment("77:101", "2").bytesize).to eq(Base64.decode64(message.part_bytes("2")).bytesize)
    end

    it "accepts a legacy bare UID without comparing UIDVALIDITY" do
      expect(adapter.attachment("101", "2")).to start_with("%PDF")
      expect(imap).not_to have_received(:status)
    end

    it "returns the bytes of a part in a nested structure" do
      stub_imap_message(imap, imap_fixture("nested"), uid: 101, validity: validity)

      expect(adapter.attachment("77:101", "2")).to start_with("%PDF")
    end

    it "returns the bytes of a single-part PDF by the path 1" do
      stub_imap_message(imap, imap_fixture("pdf_only"), uid: 101, validity: validity)

      expect(adapter.attachment("77:101", "1")).to start_with("%PDF")
    end

    context "when the part id is not a listed attachment" do
      it "raises without fetching a body for a part number that does not exist" do
        expect { adapter.attachment("77:101", "9") }.to raise_error(StandardError)
        expect(listed_body_fetches).to be_empty
      end

      it "raises without fetching a body for a text part" do
        expect { adapter.attachment("77:101", "1") }.to raise_error(StandardError)
        expect(listed_body_fetches).to be_empty
      end

      [ "", "TEXT", "2.", "2..1", "2; DELETE", "../2", "2 3", "HEADER", "BODY[TEXT]", "-1" ].each do |bad_id|
        it "raises without fetching a body for the malformed id #{bad_id.inspect}" do
          expect { adapter.attachment("77:101", bad_id) }.to raise_error(StandardError)
          expect(listed_body_fetches).to be_empty
        end
      end

      it "raises without fetching a body for an id inside a message/rfc822 part" do
        stub_imap_message(imap, imap_fixture("rfc822"), uid: 101, validity: validity)

        expect { adapter.attachment("77:101", "2.2") }.to raise_error(StandardError)
        expect(listed_body_fetches).to be_empty
      end
    end

    context "when UIDVALIDITY changed since the id was stored" do
      let(:validity) { 99 }

      it "raises before fetching the structure or any body, and not with a ThreadError" do
        expect { adapter.attachment("77:101", "2") }.to raise_error(RuntimeError, /UIDVALIDITY changed/)

        expect(calls).to be_empty
      end
    end

    it "raises when the message does not exist" do
      expect { adapter.attachment("77:999", "2") }.to raise_error(/not found/i)
    end
  end
end
