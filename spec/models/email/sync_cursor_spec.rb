require "rails_helper"

RSpec.describe Email::SyncCursor do
  include ActiveSupport::Testing::TimeHelpers

  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:email_sync_cursor)).to be_valid
    end

    it_behaves_like "requires attribute", :provider, :email_sync_cursor
    it_behaves_like "requires attribute", :account, :email_sync_cursor

    it "rejects an unknown provider" do
      expect(build(:email_sync_cursor, provider: "aol")).not_to be_valid
    end

    it "defaults the mailbox to INBOX" do
      expect(described_class.new.mailbox).to eq("INBOX")
    end

    it "enforces uniqueness of provider, account and mailbox" do
      create(:email_sync_cursor, provider: "gmail", account: "me@example.com", mailbox: "INBOX")
      duplicate = build(:email_sync_cursor, provider: "gmail", account: "me@example.com", mailbox: "INBOX")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:account]).not_to be_empty
    end

    it "enforces the uniqueness in the database" do
      create(:email_sync_cursor, provider: "gmail", account: "me@example.com")
      duplicate = build(:email_sync_cursor, provider: "gmail", account: "me@example.com")
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same account on another provider or mailbox" do
      create(:email_sync_cursor, provider: "gmail", account: "me@example.com")
      expect(build(:email_sync_cursor, provider: "yahoo", account: "me@example.com")).to be_valid
      expect(build(:email_sync_cursor, provider: "gmail", account: "me@example.com", mailbox: "Sent")).to be_valid
    end
  end

  describe "failed_runs" do
    let(:cursor) { create(:email_sync_cursor, provider: "yahoo", failed_runs: 2) }

    it "starts at 0" do
      expect(create(:email_sync_cursor, provider: "yahoo").failed_runs).to eq(0)
    end

    it "is cleared when the cursor advances" do
      cursor.advance!(uid_validity: 1, last_uid: 9)
      expect(cursor.reload.failed_runs).to eq(0)
    end

    it "is cleared when the cursor is reset" do
      cursor.reset!(uid_validity: 1, last_uid: 9)
      expect(cursor.reload.failed_runs).to eq(0)
    end
  end

  describe ".for" do
    it "builds an unsaved cursor when none exists" do
      cursor = described_class.for(provider: "gmail", account: "me@example.com")
      expect(cursor).to be_new_record
      expect(cursor).to have_attributes(provider: "gmail", account: "me@example.com", mailbox: "INBOX", history_id: nil)
    end

    it "returns the existing cursor" do
      existing = create(:email_sync_cursor, provider: "yahoo", account: "me@yahoo.com", last_uid: 7)
      expect(described_class.for(provider: "yahoo", account: "me@yahoo.com")).to eq(existing)
    end
  end

  describe "#advance!" do
    it "stores the Gmail history id, persists a new cursor and stamps last_synced_at" do
      cursor = described_class.for(provider: "gmail", account: "me@example.com")
      freeze_time do
        cursor.advance!(history_id: "100")
        expect(cursor.reload).to have_attributes(history_id: "100", last_synced_at: Time.current)
      end
    end

    it "stores the IMAP position" do
      cursor = create(:email_sync_cursor, provider: "yahoo")
      cursor.advance!(uid_validity: 5, last_uid: 40)
      expect(cursor.reload).to have_attributes(uid_validity: 5, last_uid: 40)
    end

    it "only moves forward" do
      cursor = create(:email_sync_cursor, history_id: "200")
      cursor.advance!(history_id: "150")
      expect(cursor.reload.history_id).to eq("200")
    end

    it "does not move last_uid backwards within the same uid_validity" do
      cursor = create(:email_sync_cursor, provider: "yahoo", uid_validity: 5, last_uid: 40)
      cursor.advance!(uid_validity: 5, last_uid: 10)
      expect(cursor.reload.last_uid).to eq(40)
    end

    it "still stamps last_synced_at when the position does not move" do
      cursor = create(:email_sync_cursor, history_id: "200", last_synced_at: 1.day.ago)
      freeze_time do
        cursor.advance!(history_id: "150")
        expect(cursor.reload.last_synced_at).to eq(Time.current)
      end
    end
  end

  describe "overlapping runs" do
    let!(:stored) { create(:email_sync_cursor, provider: "gmail", account: "me@example.com", history_id: "100") }

    it "does not let a run holding a stale copy rewind an advance made meanwhile" do
      stale = described_class.find(stored.id)
      described_class.find(stored.id).advance!(history_id: "200")

      stale.advance!(history_id: "150")

      expect(stored.reload.history_id).to eq("200")
    end

    it "does not let a stale reset! rewind the position within the same epoch, but still stamps the rescan" do
      stale = described_class.find(stored.id)
      described_class.find(stored.id).advance!(history_id: "200")

      stale.reset!(history_id: "150")

      expect(stored.reload).to have_attributes(history_id: "200", failed_runs: 0)
      expect(stored.last_rescan_at).not_to be_nil
    end

    it "keeps a stale IMAP last_uid from rewinding in reset! while the uid_validity is unchanged" do
      imap = create(:email_sync_cursor, provider: "yahoo", uid_validity: 5, last_uid: 10)
      stale = described_class.find(imap.id)
      described_class.find(imap.id).advance!(uid_validity: 5, last_uid: 40)

      stale.reset!(uid_validity: 5, last_uid: 20)

      expect(imap.reload.last_uid).to eq(40)
    end

    it "advances a cursor that carries an unsaved failed_runs increment" do
      stored.failed_runs += 1
      stored.advance!(history_id: "300")
      expect(stored.reload).to have_attributes(history_id: "300", failed_runs: 0)
    end
  end

  describe "#reset!" do
    it "moves to the given position even backwards and stamps last_rescan_at" do
      cursor = create(:email_sync_cursor, provider: "yahoo", uid_validity: 5, last_uid: 40)
      freeze_time do
        cursor.reset!(uid_validity: 9, last_uid: 3)
        expect(cursor.reload).to have_attributes(uid_validity: 9, last_uid: 3, last_rescan_at: Time.current,
                                                 last_synced_at: Time.current)
      end
    end

    it "clears the position when none is given" do
      cursor = create(:email_sync_cursor, history_id: "200")
      cursor.reset!
      expect(cursor.reload).to have_attributes(history_id: nil, uid_validity: nil, last_uid: nil)
      expect(cursor.last_rescan_at).not_to be_nil
    end
  end
end
