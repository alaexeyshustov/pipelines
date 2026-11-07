require "rails_helper"

RSpec.describe Email::SyncInboxJob, "#perform" do
  include ActiveSupport::Testing::TimeHelpers

  let(:imap) { Net::IMAP.allocate }
  let(:account) { "me@yahoo.com" }
  let(:validity) { 777 }
  let(:uidnext) { 21 } # the mailbox's highest UID is 20

  before do
    travel_to Time.zone.local(2026, 4, 1, 12)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(login: nil, select: nil, status: { "UIDVALIDITY" => validity, "UIDNEXT" => uidnext })
    Emails.configure(yahoo: { username: account, password: "secret" })
  end

  after { Emails.configure }

  def stub_uid_search(criteria, uids)
    allow(imap).to receive(:uid_search).with(criteria).and_return(uids)
  end

  def stub_window(*uids)
    stub_uid_search([ "SINCE", "01-Jan-2026" ], uids)
  end

  def stub_message(uid)
    raw = "Subject: Subject #{uid}\r\nFrom: hr@company.com\r\nTo: #{account}\r\n" \
          "Date: Mon, 1 Jan 2026 12:00:00 +0000\r\nContent-Type: text/plain\r\n\r\nBody #{uid}\r\n"
    allow(imap).to receive(:uid_fetch).with(uid, anything)
      .and_return([ Net::IMAP::FetchData.new(uid, { "RFC822" => raw, "UID" => uid }) ])
  end

  def stub_failing_message(uid)
    allow(imap).to receive(:uid_fetch).with(uid, anything).and_return(nil)
  end

  def cursor
    Email::SyncCursor.find_by(provider: "yahoo", account: account, mailbox: "INBOX")
  end

  def seed_cursor(uid_validity: validity, last_uid: 10)
    Email::SyncCursor.for(provider: "yahoo", account: account).advance!(uid_validity: uid_validity, last_uid: last_uid)
  end

  context "with yahoo and no cursor (first run)" do
    before do
      stub_window(3, 5)
      stub_message(3)
      stub_message(5)
    end

    it "backfills the last 90 days, stores emails under <uid_validity>:<uid> and returns counts with the new ids" do
      result = described_class.perform_now("yahoo")

      expect(result.counts).to eq("mode" => "backfill", "fetched" => 2, "stored" => 2, "duplicates" => 0, "failed" => 0)
      expect(result.email_ids).to match_array(Email.pluck(:id))
      expect(Email.order(:provider_message_id)).to contain_exactly(
        have_attributes(provider: "yahoo", provider_message_id: "777:3", subject: "Subject 3", body: "Body 3",
                        source_url: nil, date: Time.utc(2026, 1, 1, 12)),
        have_attributes(provider_message_id: "777:5")
      )
    end

    it "stores a cursor with the UIDVALIDITY and the highest UID in the mailbox (UIDNEXT - 1)" do
      described_class.perform_now("yahoo")

      expect(cursor).to have_attributes(uid_validity: 777, last_uid: 20, last_synced_at: be_present)
    end

    it "still stores the mailbox's highest UID when the window is empty, so the next run is not UID 1:*" do
      stub_window

      described_class.perform_now("yahoo")

      expect(cursor).to have_attributes(uid_validity: 777, last_uid: 20)
    end
  end

  context "with yahoo and a cursor on the same UIDVALIDITY" do
    before do
      seed_cursor(last_uid: 10)
      create(:email, provider: "yahoo", provider_message_id: "777:10")
    end

    it "stores only UIDs after the last one and advances the cursor" do
      stub_uid_search([ "UID", "11:*" ], [ 11, 12 ])
      stub_message(11)
      stub_message(12)

      result = described_class.perform_now("yahoo")

      expect(result.counts).to eq("mode" => "incremental", "fetched" => 2, "stored" => 2, "duplicates" => 0, "failed" => 0)
      expect(Email.pluck(:provider_message_id)).to include("777:11", "777:12")
      expect(cursor).to have_attributes(uid_validity: 777, last_uid: 12)
    end

    it "ignores the echo of the last message when nothing is new" do
      stub_uid_search([ "UID", "11:*" ], [ 10 ])

      result = nil
      expect { result = described_class.perform_now("yahoo") }.not_to change(Email, :count)
      expect(result.counts).to include("mode" => "incremental", "fetched" => 0, "stored" => 0)
      expect(cursor.last_uid).to eq(10)
    end

    it "does not move the cursor when an IMAP error aborts the run" do
      allow(imap).to receive(:uid_search).and_raise(Net::IMAP::NoResponseError.allocate)

      expect { described_class.perform_now("yahoo") }.to raise_error(Net::IMAP::NoResponseError)
      stored = cursor
      expect(stored).to have_attributes(last_uid: 10, last_synced_at: stored.created_at)
    end

    it "holds the cursor when a message failed, so the next run re-reads the range" do
      allow(Rails.logger).to receive(:error)
      stub_uid_search([ "UID", "11:*" ], [ 11, 12 ])
      stub_failing_message(11)
      stub_message(12)

      result = described_class.perform_now("yahoo")

      expect(result.counts).to include("stored" => 1, "failed" => 1)
      expect(Rails.logger).to have_received(:error).with(/777:11/)
      stored = cursor
      expect(stored).to have_attributes(last_uid: 10, last_synced_at: stored.created_at)
    end
  end

  context "with yahoo when UIDVALIDITY changed" do
    before do
      seed_cursor(uid_validity: 111, last_uid: 10)
      create(:email, provider: "yahoo", provider_message_id: "111:3")
      create(:email, provider: "yahoo", provider_message_id: "777:5")
      stub_window(3, 5)
      stub_message(3)
    end

    it "rescans the date window and creates new rows for the new UIDVALIDITY without collisions" do
      result = nil
      expect { result = described_class.perform_now("yahoo") }.to change(Email, :count).by(1)

      expect(result.counts).to eq("mode" => "rescan", "fetched" => 2, "stored" => 1, "duplicates" => 1, "failed" => 0)
      expect(Email.where(provider: "yahoo").pluck(:provider_message_id)).to include("111:3", "777:3", "777:5")
    end

    it "resets the cursor to the new UIDVALIDITY" do
      described_class.perform_now("yahoo")

      expect(cursor).to have_attributes(uid_validity: 777, last_uid: 20, last_rescan_at: be_present)
    end

    it "holds the old cursor when a message failed" do
      allow(Rails.logger).to receive(:error)
      stub_failing_message(3)

      described_class.perform_now("yahoo")

      expect(cursor).to have_attributes(uid_validity: 111, last_uid: 10, last_rescan_at: nil)
    end
  end

  it "stores no position when a backfill message failed, only the failed run" do
    allow(Rails.logger).to receive(:error)
    stub_window(3)
    stub_failing_message(3)

    described_class.perform_now("yahoo")

    expect(cursor).to have_attributes(uid_validity: nil, last_uid: nil, failed_runs: 1)
  end

  describe "a message that keeps failing" do
    let(:max) { Email::SyncCursor::MAX_FAILED_RUNS }

    # The same range is re-read on purpose, run after run.
    def run_failing_syncs(times)
      Prosopite.pause { times.times { described_class.perform_now("yahoo") } }
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
      seed_cursor(last_uid: 10)
      stub_uid_search([ "UID", "11:*" ], [ 11, 12 ])
      stub_failing_message(11)
      stub_message(12)
    end

    it "holds the cursor and counts the failed run until MAX_FAILED_RUNS" do
      run_failing_syncs(max - 1)

      expect(cursor).to have_attributes(last_uid: 10, failed_runs: max - 1)
    end

    it "moves the cursor on at the MAX_FAILED_RUNS-th failed run, resets the count and logs the failed ids" do
      run_failing_syncs(max)

      expect(cursor).to have_attributes(last_uid: 12, failed_runs: 0)
      expect(Rails.logger).to have_received(:warn).with(/yahoo.*777:11/)
    end
  end
end
