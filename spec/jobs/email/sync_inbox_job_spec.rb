require "rails_helper"

RSpec.describe Email::SyncInboxJob do
  include GmailHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { GmailHelpers::GMAIL_BASE_URL }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:account) { "me@gmail.com" }
  let(:profile_history_id) { "500" }

  before do
    setup_gmail
    travel_to Time.zone.local(2026, 4, 1, 12)
    stub_request(:get, "#{base}/profile")
      .to_return(status: 200, headers: json, body: { emailAddress: account, historyId: profile_history_id }.to_json)
  end

  after do
    teardown_gmail
  end

  def stub_message(id)
    stub_request(:get, %r{#{base}/messages/#{id}\?format=full})
      .to_return(status: 200, headers: json, body: gmail_message_json(id: id, subject: "Subject #{id}"))
  end

  def stub_window(*ids, since: "after:2026/01/01")
    stub_request(:get, "#{base}/messages").with(query: hash_including("q" => since, "labelIds" => "INBOX"))
      .to_return(status: 200, headers: json, body: { messages: ids.map { |id| { id: id } } }.to_json)
  end

  def stub_history(*ids, status: 200, start: "100")
    body = { history: [ { id: "1", messagesAdded: ids.map { |id| { message: { id: id } } } } ] }
    stub_request(:get, "#{base}/history").with(query: hash_including("startHistoryId" => start))
      .to_return(status: status, headers: json, body: body.to_json)
  end

  def cursor
    Email::SyncCursor.find_by(provider: "gmail", account: account, mailbox: "INBOX")
  end

  context "without a cursor (first run)" do
    before do
      stub_window("m1", "m2")
      stub_message("m1")
      stub_message("m2")
    end

    it "backfills the last 90 days, stores the emails and returns counts with the new ids" do
      result = described_class.perform_now("gmail")

      expect(result.counts).to eq("mode" => "backfill", "fetched" => 2, "stored" => 2, "duplicates" => 0, "failed" => 0)
      expect(result.email_ids).to match_array(Email.pluck(:id))
      expect(Email.order(:provider_message_id)).to contain_exactly(
        have_attributes(provider: "gmail", provider_message_id: "m1", subject: "Subject m1",
                        source_url: "https://mail.google.com/mail/u/0/#inbox/m1", date: Time.utc(2026, 1, 1, 12)),
        have_attributes(provider_message_id: "m2")
      )
    end

    it "stores a cursor holding the historyId captured from the profile" do
      described_class.perform_now("gmail")

      expect(cursor).to have_attributes(history_id: "500", last_synced_at: be_present)
    end

    it "uses the backfill window from the Setting" do
      Setting.set("email_backfill_days", "30")
      stub_window("m1", since: "after:2026/03/02")

      expect(described_class.perform_now("gmail").counts).to include("mode" => "backfill", "fetched" => 1)
    end
  end

  context "with a cursor" do
    before do
      Email::SyncCursor.for(provider: "gmail", account: account).advance!(history_id: "100")
      create(:email, provider: "gmail", provider_message_id: "old")
    end

    it "stores only the new INBOX messages and advances the cursor" do
      stub_history("old", "new1")
      stub_message("new1")

      result = described_class.perform_now("gmail")

      expect(result.counts).to eq("mode" => "incremental", "fetched" => 2, "stored" => 1, "duplicates" => 1, "failed" => 0)
      expect(result.email_ids).to eq([ Email.find_by!(provider_message_id: "new1").id ])
      expect(cursor.history_id).to eq("500")
    end

    it "stores nothing and still advances when nothing is new" do
      stub_request(:get, "#{base}/history").with(query: hash_including({}))
        .to_return(status: 200, headers: json, body: { historyId: "500" }.to_json)

      expect(described_class.perform_now("gmail").counts).to include("fetched" => 0, "stored" => 0)
      expect(cursor.history_id).to eq("500")
    end

    it "stores nothing new when re-run over the same history" do
      stub_history("new1")
      stub_history("new1", start: "500")
      stub_message("new1")
      described_class.perform_now("gmail")

      result = nil
      expect { result = described_class.perform_now("gmail") }.not_to change(Email, :count)
      expect(result.counts).to include("stored" => 0, "duplicates" => 1)
      expect(result.email_ids).to eq([])
    end

    it "falls back to a date-window rescan on a 404, creates no duplicates and resets the cursor" do
      stub_history(status: 404)
      stub_window("old", "m9")
      stub_message("m9")

      result = nil
      expect { result = described_class.perform_now("gmail") }.to change(Email, :count).by(1)

      expect(result.counts).to eq("mode" => "rescan", "fetched" => 2, "stored" => 1, "duplicates" => 1, "failed" => 0)
      expect(cursor).to have_attributes(history_id: "500", last_rescan_at: be_present)
    end

    it "does not advance the cursor when a provider error aborts the run" do
      stub_history(status: 500)

      expect { described_class.perform_now("gmail") }.to raise_error(Google::Apis::ServerError)
      stored = cursor
      expect(stored.history_id).to eq("100")
      expect(stored.last_synced_at).to eq(stored.created_at)
    end

    it "logs and counts a message that cannot be fetched, and keeps going" do
      allow(Rails.logger).to receive(:error)
      stub_history("bad", "good")
      stub_request(:get, %r{#{base}/messages/bad\?format=full}).to_return(status: 500, headers: json, body: "{}")
      stub_message("good")

      result = described_class.perform_now("gmail")

      expect(result.counts).to include("fetched" => 2, "stored" => 1, "failed" => 1)
      expect(Rails.logger).to have_received(:error).with(/bad/)
    end

    it "holds the cursor when a message failed, so the next run re-reads the range" do
      allow(Rails.logger).to receive(:error)
      stub_history("bad", "good")
      stub_request(:get, %r{#{base}/messages/bad\?format=full}).to_return(status: 500, headers: json, body: "{}")
      stub_message("good")

      described_class.perform_now("gmail")

      stored = cursor
      expect(stored).to have_attributes(history_id: "100", last_rescan_at: nil)
      expect(stored.last_synced_at).to eq(stored.created_at)
    end

    it "holds the cursor when a failure happens during a 404 rescan" do
      allow(Rails.logger).to receive(:error)
      stub_history(status: 404)
      stub_window("bad")
      stub_request(:get, %r{#{base}/messages/bad\?format=full}).to_return(status: 500, headers: json, body: "{}")

      described_class.perform_now("gmail")

      expect(cursor).to have_attributes(history_id: "100", last_rescan_at: nil)
    end
  end

  it "does not store a cursor when a backfill message failed" do
    allow(Rails.logger).to receive(:error)
    stub_window("bad", "good")
    stub_request(:get, %r{#{base}/messages/bad\?format=full}).to_return(status: 500, headers: json, body: "{}")
    stub_message("good")

    result = described_class.perform_now("gmail")

    expect(result.counts).to include("stored" => 1, "failed" => 1)
    expect(Email::SyncCursor.count).to eq(0)
  end

  it "does not store a cursor when the first run aborts" do
    stub_request(:get, "#{base}/messages").with(query: hash_including({})).to_return(status: 500, headers: json, body: "{}")

    expect { described_class.perform_now("gmail") }.to raise_error(Google::Apis::ServerError)
    expect(Email::SyncCursor.count).to eq(0)
  end

  it "rejects providers it cannot sync yet" do
    expect { described_class.perform_now("aol") }.to raise_error(ArgumentError, /aol/)
  end
end
