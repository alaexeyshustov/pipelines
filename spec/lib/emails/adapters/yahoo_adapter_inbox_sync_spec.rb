require "rails_helper"

RSpec.describe Emails::Adapters::YahooAdapter do
  include ImapResponseHelpers

  subject(:adapter) { described_class.new(host: "imap.mail.yahoo.com", port: 993, username: "me@yahoo.com", password: "secret") }

  let(:imap) { Net::IMAP.allocate }

  before do
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(login: nil, select: nil)
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

      expect(adapter.inbox_uids_since(Time.utc(2026, 1, 1))).to eq([ 3, 5 ])
      expect(imap).to have_received(:uid_search).with([ "SINCE", "01-Jan-2026" ])
    end

    it "adds BEFORE from the upper bound (the day after date_to)" do
      allow(imap).to receive(:uid_search).and_return([ 3 ])

      adapter.inbox_uids_since(Time.utc(2026, 1, 1), before: Time.utc(2026, 1, 11))

      expect(imap).to have_received(:uid_search).with([ "SINCE", "01-Jan-2026", "BEFORE", "11-Jan-2026" ])
    end
  end

  describe "#fetch_message" do
    let(:message) { imap_fixture("alternative") }
    let!(:calls) { stub_imap_message(imap, message, uid: 101) }

    it "returns plain and html bodies, a parsed date and a composite id" do
      result = adapter.fetch_message("77:101")

      expect(result).to include(
        id: "77:101", provider: "yahoo", subject: "Interview invitation", from: "hr@company.com", to: "test@yahoo.com",
        html_body: "<html><body><p>Dear candidate,</p><p>Please see the invitation.</p></body></html>", source_url: nil, date: Time.utc(2026, 1, 1, 12)
      )
      expect(result[:body]).to start_with("Dear candidate,")
    end

    it "gives the same body and html_body as parsing the full raw message" do
      legacy = Emails::Adapters::ImapBodyParser.new(Mail.new(message.raw))

      expect(adapter.fetch_message("77:101")).to include(body: legacy.body, html_body: legacy.html)
    end

    it "fetches the structure and header, then only the text parts, never RFC822" do
      adapter.fetch_message("77:101")

      expect(calls.flatten).not_to include("RFC822")
      expect(calls.first).to include("BODYSTRUCTURE")
      expect(calls.drop(1)).to eq([ %w[BODY.PEEK[1]<0.1048576> BODY.PEEK[2]<0.1048576>] ])
    end

    it "prefixes a bare UID with the current INBOX UIDVALIDITY" do
      allow(imap).to receive(:status).and_return({ "UIDVALIDITY" => 77 })

      expect(adapter.fetch_message("101")).to include(id: "77:101")
    end

    it "raises when the message does not exist" do
      expect { adapter.fetch_message("77:102") }.to raise_error(/not found/)
    end

    it "raises when the message has no usable date" do
      dated = imap_text_message("body")
      stub_imap_message(imap, dated.with(raw: dated.raw.sub(/Date: [^\r]*\r\n/, "")), uid: 101)

      expect { adapter.fetch_message("77:101") }.to raise_error(ArgumentError, /date/)
    end

    it "reads a large-attachment message through its text parts only" do
      large = imap_fixture("mixed_pdf", structure: "mixed_large_pdf")
      large_calls = stub_imap_message(imap, large, uid: 101)

      result = adapter.fetch_message("77:101")

      expect(result[:body]).to eq("Please find my CV attached.")
      expect(large_calls.drop(1)).to eq([ [ "BODY.PEEK[1]<0.1048576>" ] ])
    end
  end

  describe "#message" do
    let(:message) { imap_text_message("Hi") }
    let!(:calls) { stub_imap_message(imap, message, uid: 101) }

    it "accepts the legacy bare UID" do
      expect(adapter.message("101")).to include(subject: "Generated")
    end

    it "accepts a <uid_validity>:<uid> id" do
      expect(adapter.message("77:101")).to include(subject: "Generated")
      expect(imap).to have_received(:uid_fetch).with(101, anything).at_least(:once)
    end

    it "agrees with #fetch_message on subject, from, to and body" do
      alternative = imap_fixture("alternative")
      stub_imap_message(imap, alternative, uid: 101)

      expect(adapter.message("101")).to include(adapter.fetch_message("77:101").slice(:subject, :from, :to, :body))
    end

    it "does not fetch RFC822" do
      adapter.message("101")

      expect(calls.flatten).not_to include("RFC822")
    end
  end
end
