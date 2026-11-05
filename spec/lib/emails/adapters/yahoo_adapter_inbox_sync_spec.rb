require "rails_helper"

RSpec.describe Emails::Adapters::YahooAdapter do
  subject(:adapter) { described_class.new(host: "imap.mail.yahoo.com", port: 993, username: "me@yahoo.com", password: "secret") }

  let(:imap) { Net::IMAP.allocate }

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(login: nil, select: nil)
  end

  def fetch_data(uid, raw)
    [ Net::IMAP::FetchData.new(uid, { "RFC822" => raw, "FLAGS" => [], "UID" => uid }) ]
  end

  describe "#account" do
    it "is the login username" do
      expect(adapter.account).to eq("me@yahoo.com")
    end
  end

  describe "#inbox_uid_validity" do
    it "returns the INBOX UIDVALIDITY" do
      allow(imap).to receive(:status).with("INBOX", [ "UIDVALIDITY" ]).and_return({ "UIDVALIDITY" => 1_700_000_001 })

      expect(adapter.inbox_uid_validity).to eq(1_700_000_001)
    end
  end

  describe "#inbox_status" do
    it "returns UIDVALIDITY and the highest UID (UIDNEXT - 1) from one STATUS call" do
      allow(imap).to receive(:status).with("INBOX", %w[UIDVALIDITY UIDNEXT]).and_return({ "UIDVALIDITY" => 77, "UIDNEXT" => 31 })

      expect(adapter.inbox_status).to have_attributes(uid_validity: 77, last_uid: 30)
    end

    it "reports 0 as the highest UID of an empty mailbox" do
      allow(imap).to receive(:status).and_return({ "UIDVALIDITY" => 77, "UIDNEXT" => 1 })

      expect(adapter.inbox_status.last_uid).to eq(0)
    end
  end

  describe "#inbox_uids_after" do
    it "searches from last_uid + 1 and returns the newer UIDs in ascending order" do
      allow(imap).to receive(:uid_search).and_return([ 12, 11 ])

      expect(adapter.inbox_uids_after(10)).to eq([ 11, 12 ])
      expect(imap).to have_received(:select).with("INBOX")
      expect(imap).to have_received(:uid_search).with([ "UID", "11:*" ])
    end

    it "drops the echo of the last message that IMAP returns when nothing is newer" do
      allow(imap).to receive(:uid_search).and_return([ 10 ])

      expect(adapter.inbox_uids_after(10)).to eq([])
    end
  end

  describe "#inbox_uids_since" do
    it "returns the UIDs of INBOX messages on or after the date, ascending" do
      allow(imap).to receive(:uid_search).and_return([ 5, 3 ])

      expect(adapter.inbox_uids_since(Date.new(2026, 1, 1))).to eq([ 3, 5 ])
      expect(imap).to have_received(:uid_search).with([ "SINCE", "01-Jan-2026" ])
    end
  end

  describe "#fetch_message" do
    let(:raw) do
      "Subject: Hello\r\nFrom: hr@company.com\r\nTo: me@yahoo.com\r\nDate: Mon, 1 Jan 2026 12:00:00 +0000\r\n" \
        "MIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"b\"\r\n\r\n" \
        "--b\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nPlain text\r\n" \
        "--b\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n<p>Html text</p>\r\n--b--\r\n"
    end

    before do
      allow(imap).to receive(:uid_fetch).with(101, anything).and_return(fetch_data(101, raw))
    end

    it "returns plain and html bodies, a parsed date and a composite id" do
      message = adapter.fetch_message("77:101")

      expect(message).to include(
        id: "77:101", provider: "yahoo", subject: "Hello", from: "hr@company.com", to: "me@yahoo.com",
        body: "Plain text", html_body: "<p>Html text</p>", source_url: nil, date: Time.utc(2026, 1, 1, 12)
      )
    end

    it "prefixes a bare UID with the current INBOX UIDVALIDITY" do
      allow(imap).to receive(:status).and_return({ "UIDVALIDITY" => 77 })

      expect(adapter.fetch_message("101")).to include(id: "77:101")
    end

    it "raises when the message does not exist" do
      allow(imap).to receive(:uid_fetch).with(102, anything).and_return(nil)

      expect { adapter.fetch_message("77:102") }.to raise_error(/not found/)
    end

    it "raises when the message has no usable date" do
      allow(imap).to receive(:uid_fetch).with(101, anything).and_return(fetch_data(101, "Subject: x\r\n\r\nbody"))

      expect { adapter.fetch_message("77:101") }.to raise_error(ArgumentError, /date/)
    end
  end

  describe "#get_message" do
    let(:raw) { "Subject: Legacy\r\nFrom: a@b.com\r\nTo: me@yahoo.com\r\nDate: Mon, 1 Jan 2026 12:00:00 +0000\r\n\r\nHi\r\n" }

    before do
      allow(imap).to receive(:uid_fetch).with(101, anything).and_return(fetch_data(101, raw))
    end

    it "accepts the legacy bare UID" do
      expect(adapter.get_message("101")).to include(subject: "Legacy")
    end

    it "accepts a <uid_validity>:<uid> id" do
      expect(adapter.get_message("77:101")).to include(subject: "Legacy")
      expect(imap).to have_received(:uid_fetch).with(101, anything)
    end
  end
end
