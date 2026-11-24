require "rails_helper"

RSpec.describe Email::InboxSync do
  include ActiveSupport::Testing::TimeHelpers
  include EmailAdapterHelpers

  let(:today) { Date.new(2026, 4, 1) }
  let(:account) { EmailAdapterHelpers::GMAIL_ACCOUNT }
  let(:max) { Email::SyncCursor::MAX_FAILED_RUNS }
  let(:synced_at) { Time.zone.local(2026, 3, 20, 10) } # the window start W is the day before: 2026-03-19
  let(:window_start) { Date.new(2026, 3, 19) }
  let(:backfill_start) { today - 90 } # 2026-01-01

  before do
    travel_to Time.zone.local(2026, 4, 1, 12)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
  end

  after { Emails.configure }

  def at(date) = Time.zone.local(date.year, date.month, date.day)

  def cursor(provider: "gmail", acct: account) = Email::SyncCursor.find_by(provider:, account: acct, mailbox: "INBOX")

  def sync(provider: "gmail", date_from: nil, date_to: nil)
    described_class.call(provider:, date_from:, date_to:)
  end

  describe "Gmail" do
    let(:adapter) do
      stub_gmail_adapter(inbox_message_ids_since: %w[new1], inbox_message_ids_after: %w[w1 w2]).tap do |double|
        %w[new1 w1 w2 bad].each { |id| allow(double).to receive(:fetch_message).with(id).and_return(adapter_message(id)) }
      end
    end

    before { adapter }

    def usable_cursor(history_id: "100", last_synced_at: synced_at, **attrs)
      create(:email_sync_cursor, provider: "gmail", account:, history_id:, last_synced_at:, **attrs)
    end

    describe "the result" do
      it "carries the mode, the counts and the ids of the newly stored emails only" do
        usable_cursor
        create(:email, provider: "gmail", provider_message_id: "new1")
        allow(adapter).to receive(:inbox_message_ids_since).and_return(%w[new1 w1])

        result = sync

        expect(result.mode.to_s).to eq("incremental")
        expect(result.counts).to include("fetched" => 2, "stored" => 1, "duplicates" => 1, "failed" => 0)
        expect(result.email_ids).to eq([ Email.find_by!(provider_message_id: "w1").id ])
      end

      it "stores the fetched message fields" do
        usable_cursor

        sync

        expect(Email.find_by!(provider_message_id: "new1")).to have_attributes(
          provider: "gmail", from_address: "hr@acme.com", subject: "Subject new1", body: "Body new1", date: Time.utc(2026, 3, 1, 12)
        )
      end
    end

    describe "incremental mode" do
      before { usable_cursor }

      it "is used with blank dates, reads the history since the cursor and advances it", :aggregate_failures do
        result = sync

        expect(result.mode.to_s).to eq("incremental")
        expect(adapter).to have_received(:inbox_message_ids_since).with("100")
        expect(adapter).not_to have_received(:inbox_message_ids_after)
        expect(cursor).to have_attributes(history_id: "500", failed_runs: 0)
        expect(cursor.last_synced_at).to be > synced_at
      end

      it "is used when date_to is today, which counts as open-ended" do
        expect(sync(date_from: window_start, date_to: today).mode.to_s).to eq("incremental")
      end

      [ [ "equals W", Date.new(2026, 3, 19) ], [ "is after W", Date.new(2026, 3, 25) ] ].each do |label, from|
        it "is used when date_from #{label}, and mail received before date_from is kept" do
          allow(adapter).to receive(:inbox_message_ids_since).and_return(%w[w1])
          allow(adapter).to receive(:fetch_message).with("w1").and_return(adapter_message("w1", date: Time.utc(2026, 1, 5)))

          result = sync(date_from: from)

          expect(result.mode.to_s).to eq("incremental")
          expect(Email.find_by(provider_message_id: "w1")).to be_present
          expect(adapter).not_to have_received(:inbox_message_ids_after)
        end
      end

      it "stores nothing and still advances when nothing is new" do
        allow(adapter).to receive(:inbox_message_ids_since).and_return([])

        expect(sync.counts).to include("fetched" => 0, "stored" => 0)
        expect(cursor.history_id).to eq("500")
      end

      it "does not advance the cursor when the provider raises" do
        allow(adapter).to receive(:inbox_message_ids_since).and_raise(Google::Apis::ServerError.new("boom"))

        expect { sync }.to raise_error(Email::InboxSync::Failure, /ServerError.*boom/)
        expect(cursor.history_id).to eq("100")
      end

      it "reports the mode and the cause in the failure" do
        allow(adapter).to receive(:inbox_message_ids_since).and_raise(Google::Apis::ServerError.new("boom"))

        expect { sync }.to raise_error(Email::InboxSync::Failure) do |error|
          expect([ error.mode, error.cause ]).to match([ "incremental", an_instance_of(Google::Apis::ServerError) ])
        end
      end

      it "beats the heartbeat for every listed message" do
        allow(adapter).to receive(:inbox_message_ids_since).and_return(%w[new1 w1 w2])
        allow(Orchestration::Heartbeat).to receive(:beat)

        sync

        expect(Orchestration::Heartbeat).to have_received(:beat).exactly(3).times
      end
    end

    describe "window mode" do
      it "is used when date_from is before W, lists from date_from to now, and resets the cursor", :aggregate_failures do
        usable_cursor

        result = sync(date_from: Date.new(2026, 3, 1))

        expect(result.mode.to_s).to eq("window")
        expect(adapter).to have_received(:inbox_message_ids_after).with(at(Date.new(2026, 3, 1)), before: nil)
        expect(adapter).not_to have_received(:inbox_message_ids_since)
        expect(cursor).to have_attributes(history_id: "500", last_rescan_at: be_present, failed_runs: 0)
      end

      it "treats date_to = today as open-ended: window, reset, no historical shortcut" do
        usable_cursor

        result = sync(date_from: Date.new(2026, 3, 1), date_to: today)

        expect(result.mode.to_s).to eq("window")
        expect(cursor.last_rescan_at).to be_present
      end

      it "is used for a cursor row without a position, from backfill_days ago, and resets the cursor" do
        create(:email_sync_cursor, provider: "gmail", account:, failed_runs: 1)

        result = sync

        expect(result.mode.to_s).to eq("window")
        expect(adapter).to have_received(:inbox_message_ids_after).with(at(backfill_start), before: nil)
        expect(cursor).to have_attributes(history_id: "500", failed_runs: 0, last_synced_at: be_present)
      end

      it "is used for a cursor that has a history id but never finished a sync (no last_synced_at)" do
        usable_cursor(last_synced_at: nil)

        expect(sync.mode.to_s).to eq("window")
        expect(adapter).not_to have_received(:inbox_message_ids_since)
      end

      it "is used without any cursor, from backfill_days ago (the Setting), and creates the cursor", :aggregate_failures do
        Setting.set("email_backfill_days", "30")

        result = sync

        expect(result.mode.to_s).to eq("window")
        expect(adapter).to have_received(:inbox_message_ids_after).with(at(today - 30), before: nil)
        expect(result.counts).to include("fetched" => 2, "stored" => 2)
        expect(cursor).to have_attributes(history_id: "500", last_synced_at: be_present)
      end

      it "starts at date_from when there is no cursor" do
        sync(date_from: Date.new(2026, 3, 10))

        expect(adapter).to have_received(:inbox_message_ids_after).with(at(Date.new(2026, 3, 10)), before: nil)
        expect(cursor.history_id).to eq("500")
      end

      it "uses Time bounds in the app time zone" do
        Time.use_zone("Asia/Tokyo") do
          sync(date_from: Date.new(2026, 3, 1))

          expect(adapter).to have_received(:inbox_message_ids_after).with(Time.zone.local(2026, 3, 1), before: nil)
        end
      end
    end

    describe "historical mode" do
      let(:range) { { date_from: Date.new(2026, 3, 1), date_to: Date.new(2026, 3, 10) } }

      it "lists only that range, with an exclusive upper bound at the start of the day after date_to", :aggregate_failures do
        result = sync(**range)

        expect(result.mode.to_s).to eq("historical")
        expect(adapter).to have_received(:inbox_message_ids_after).with(at(Date.new(2026, 3, 1)), before: at(Date.new(2026, 3, 11)))
        expect(adapter).not_to have_received(:inbox_message_ids_since)
        expect(result.counts).to include("fetched" => 2, "stored" => 2)
      end

      it "leaves an existing cursor row untouched" do
        usable_cursor(failed_runs: 1)
        before_state = cursor.attributes

        sync(**range)

        expect(cursor.reload.attributes).to eq(before_state)
      end

      it "creates no cursor when there is none" do
        sync(**range)

        expect(Email::SyncCursor.count).to eq(0)
      end

      it "does not even count a failed run on the cursor" do
        usable_cursor
        allow(adapter).to receive(:fetch_message).with("w1").and_raise("boom")

        result = sync(**range)

        expect(result.counts).to include("failed" => 1)
        expect(cursor).to have_attributes(history_id: "100", failed_runs: 0)
      end
    end

    describe "rescan_window mode (Gmail no longer has the history)" do
      before do
        usable_cursor
        allow(adapter).to receive(:inbox_message_ids_since).and_raise(Emails::HistoryExpiredError, "gone")
      end

      it "rescans [W, now] and then resets the cursor" do
        result = sync

        expect(result.mode.to_s).to eq("rescan_window")
        expect(adapter).to have_received(:inbox_message_ids_after).with(at(window_start), before: nil)
        expect(cursor).to have_attributes(history_id: "500", last_rescan_at: be_present)
      end

      it "creates no duplicates of mail the window shares with what is stored" do
        create(:email, provider: "gmail", provider_message_id: "w1")

        result = sync

        expect(result.counts).to include("fetched" => 2, "stored" => 1, "duplicates" => 1)
      end
    end

    describe "failed messages hold the cursor (MAX_FAILED_RUNS)" do
      before do
        allow(adapter).to receive(:inbox_message_ids_since).and_return(%w[bad new1])
        allow(adapter).to receive(:fetch_message).with("bad").and_raise("cannot fetch")
      end

      # The same range is re-read on purpose, run after run.
      def run_failing(times, **args)
        Prosopite.pause { times.times { sync(**args) } }
      end

      it "logs and counts a failed message, keeps going, and holds an incremental cursor" do
        usable_cursor

        result = sync

        expect(result.counts).to include("fetched" => 2, "stored" => 1, "failed" => 1)
        expect(Rails.logger).to have_received(:error).with(/bad/)
        expect(cursor).to have_attributes(history_id: "100", failed_runs: 1)
      end

      it "counts failed runs until MAX_FAILED_RUNS" do
        usable_cursor

        run_failing(max - 1)

        expect(cursor).to have_attributes(history_id: "100", failed_runs: max - 1)
        expect(Rails.logger).not_to have_received(:warn)
      end

      it "moves the cursor on at the MAX_FAILED_RUNS-th failed run, clears the count and logs the failed ids" do
        usable_cursor

        run_failing(max)

        expect(cursor).to have_attributes(history_id: "500", failed_runs: 0)
        expect(Rails.logger).to have_received(:warn).with(/gmail.*bad/)
      end

      it "holds a window reset that had a failed message and counts the failed run" do
        allow(adapter).to receive(:inbox_message_ids_after).and_return(%w[bad w1])
        usable_cursor

        sync(date_from: Date.new(2026, 3, 1))

        expect(cursor).to have_attributes(history_id: "100", last_rescan_at: nil, failed_runs: 1)
      end

      it "releases the held window reset at MAX_FAILED_RUNS and resets the cursor", :aggregate_failures do
        allow(adapter).to receive(:inbox_message_ids_after).and_return(%w[bad w1])
        usable_cursor(failed_runs: max - 1)

        sync(date_from: Date.new(2026, 3, 1))

        expect(cursor).to have_attributes(history_id: "500", last_rescan_at: be_present, failed_runs: 0)
        expect(Rails.logger).to have_received(:warn).with(/bad/)
      end

      it "holds the cursor too when a rescan_window fails" do
        usable_cursor
        allow(adapter).to receive(:inbox_message_ids_since).and_raise(Emails::HistoryExpiredError)
        allow(adapter).to receive(:inbox_message_ids_after).and_return(%w[bad])

        sync

        expect(cursor).to have_attributes(history_id: "100", last_rescan_at: nil, failed_runs: 1)
      end

      it "stores no position for a first window with a failed message, only the failed run" do
        allow(adapter).to receive(:inbox_message_ids_after).and_return(%w[bad w1])

        sync

        expect(cursor).to have_attributes(history_id: nil, last_synced_at: nil, failed_runs: 1)
      end
    end

    it "counts a message stored concurrently by another run as a duplicate" do
      allow(Email).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      result = sync

      expect(result.counts).to include("fetched" => 2, "stored" => 0, "duplicates" => 2, "failed" => 0)
    end

    it "does not store a cursor when the first run aborts" do
      allow(adapter).to receive(:inbox_message_ids_after).and_raise(Google::Apis::ServerError.new("boom"))

      expect { sync }.to raise_error(Email::InboxSync::Failure) { |error| expect(error.mode).to eq("window") }
      expect(Email::SyncCursor.count).to eq(0)
    end
  end

  describe "Yahoo (IMAP)" do
    let(:account) { EmailAdapterHelpers::YAHOO_ACCOUNT }
    let(:adapter) do
      stub_yahoo_adapter(inbox_uids_after: [ 11, 12 ], inbox_uids_since: [ 3, 5 ]).tap do |double|
        [ 3, 5, 11, 12 ].each do |uid|
          allow(double).to receive(:fetch_message).with("777:#{uid}")
                                                  .and_return(adapter_message("777:#{uid}", provider: "yahoo"))
        end
      end
    end

    before { adapter }

    def yahoo_cursor(uid_validity: 777, last_uid: 10, last_synced_at: synced_at, **attrs)
      create(:email_sync_cursor, provider: "yahoo", account:, uid_validity:, last_uid:, last_synced_at:, **attrs)
    end

    def yahoo_sync(**args) = sync(provider: "yahoo", **args)

    def yahoo_cursor_row = cursor(provider: "yahoo")

    it "reads UIDs above last_uid incrementally with blank dates and advances to the highest listed UID", :aggregate_failures do
      yahoo_cursor

      result = yahoo_sync

      expect(result.mode.to_s).to eq("incremental")
      expect(adapter).to have_received(:inbox_uids_after).with(10)
      expect(result.counts).to include("fetched" => 2, "stored" => 2)
      expect(Email.pluck(:provider_message_id)).to contain_exactly("777:11", "777:12")
      expect(yahoo_cursor_row).to have_attributes(uid_validity: 777, last_uid: 12)
    end

    it "keeps the incremental position when nothing is new" do
      yahoo_cursor
      allow(adapter).to receive(:inbox_uids_after).and_return([])

      yahoo_sync

      expect(yahoo_cursor_row).to have_attributes(uid_validity: 777, last_uid: 10)
    end

    it "is incremental when date_from is not before W" do
      yahoo_cursor

      expect(yahoo_sync(date_from: window_start).mode.to_s).to eq("incremental")
    end

    it "uses a window when date_from is before W and resets to the mailbox's highest UID" do
      yahoo_cursor

      result = yahoo_sync(date_from: Date.new(2026, 3, 1))

      expect(result.mode.to_s).to eq("window")
      expect(adapter).to have_received(:inbox_uids_since).with(at(Date.new(2026, 3, 1)), before: nil)
      expect(yahoo_cursor_row).to have_attributes(uid_validity: 777, last_uid: 20, last_rescan_at: be_present)
    end

    it "uses a window from backfill_days ago without a cursor and stores the highest UID even for an empty window" do
      allow(adapter).to receive(:inbox_uids_since).and_return([])

      result = yahoo_sync

      expect(result.mode.to_s).to eq("window")
      expect(adapter).to have_received(:inbox_uids_since).with(at(backfill_start), before: nil)
      expect(yahoo_cursor_row).to have_attributes(uid_validity: 777, last_uid: 20)
    end

    it "rescans [W, now] and resets the cursor when UIDVALIDITY changed", :aggregate_failures do
      yahoo_cursor(uid_validity: 111)

      result = yahoo_sync

      expect(result.mode.to_s).to eq("rescan_window")
      expect(adapter).to have_received(:inbox_uids_since).with(at(window_start), before: nil)
      expect(adapter).not_to have_received(:inbox_uids_after)
      expect(yahoo_cursor_row).to have_attributes(uid_validity: 777, last_uid: 20, last_rescan_at: be_present)
    end

    it "is historical for a past date_to: bounded range, cursor untouched" do
      yahoo_cursor
      before_state = yahoo_cursor_row.attributes

      result = yahoo_sync(date_from: Date.new(2026, 3, 1), date_to: Date.new(2026, 3, 10))

      expect(result.mode.to_s).to eq("historical")
      expect(adapter).to have_received(:inbox_uids_since).with(at(Date.new(2026, 3, 1)), before: at(Date.new(2026, 3, 11)))
      expect(yahoo_cursor_row.reload.attributes).to eq(before_state)
    end

    it "holds the cursor on a failed message, like Gmail" do
      yahoo_cursor
      allow(adapter).to receive(:fetch_message).with("777:11").and_raise("cannot fetch")

      result = yahoo_sync

      expect(result.counts).to include("failed" => 1, "stored" => 1)
      expect(yahoo_cursor_row).to have_attributes(last_uid: 10, failed_runs: 1)
    end
  end

  describe "errors" do
    it "rejects providers it cannot sync" do
      expect { sync(provider: "aol") }.to raise_error(ArgumentError, /aol/)
    end

    it "lets Emails::NotConfigured through, for the caller to report as skipped" do
      stub_unconfigured_adapter("gmail")

      expect { sync }.to raise_error(Emails::NotConfigured)
    end
  end
end
