require "rails_helper"

RSpec.describe Orchestration::Executors::EmailsSync do
  def sync_result(mode: "incremental", fetched: 2, stored: 1, duplicates: 1, failed: 0)
    counts = { "mode" => mode, "fetched" => fetched, "stored" => stored, "duplicates" => duplicates, "failed" => failed }
    Email::SyncInboxJob::Result.new(counts: counts, email_ids: [])
  end

  describe ".call" do
    it "syncs gmail and yahoo inline and reports the counts per provider, with nothing enqueued yet" do
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result(stored: 1))
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result(mode: "backfill", fetched: 3, stored: 3, duplicates: 0))

      expect(described_class.call).to eq(
        "gmail" => { "mode" => "incremental", "fetched" => 2, "stored" => 1, "duplicates" => 1, "failed" => 0, "enqueued" => 0 },
        "yahoo" => { "mode" => "backfill", "fetched" => 3, "stored" => 3, "duplicates" => 0, "failed" => 0, "enqueued" => 0 }
      )
    end

    it "reports a provider without credentials as skipped and still syncs the other" do
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result)
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo")
        .and_raise(RuntimeError, "Missing Yahoo credentials. Please set YAHOO_USERNAME and YAHOO_APP_PASSWORD environment variables.")

      output = described_class.call

      expect(output.fetch("yahoo")).to eq("skipped" => true, "reason" => "no credentials")
      expect(output.fetch("gmail")).to include("stored" => 1)
    end

    it "skips gmail when its credentials file is missing" do
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail")
        .and_raise(RuntimeError, "Missing Gmail credentials file. Please create credentials.json with your Google API credentials.")
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result)

      expect(described_class.call.fetch("gmail")).to eq("skipped" => true, "reason" => "no credentials")
    end

    context "when a provider fails" do
      before do
        allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_raise(Faraday::ConnectionFailed, "boom")
        allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result(stored: 4, fetched: 4, duplicates: 0))
      end

      it "still syncs the other provider" do
        expect { described_class.call }.to raise_error(described_class::ProviderFailure)
        expect(Email::SyncInboxJob).to have_received(:perform_now).with("yahoo")
      end

      it "raises afterwards, naming the failure" do
        expect { described_class.call }.to raise_error(described_class::ProviderFailure, /gmail: Faraday::ConnectionFailed: boom/)
      end

      it "keeps the successful provider's counts in the error message" do
        expect { described_class.call }.to raise_error(described_class::ProviderFailure, /"yahoo":\{.*"stored":4/)
      end
    end

    it "raises when a provider stored messages but failed on some" do
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result(failed: 1))
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result)

      expect { described_class.call }.to raise_error(described_class::ProviderFailure, /gmail: 1 message\(s\) failed/)
    end

    it "does not swallow an unrelated RuntimeError as a skip" do
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_raise(RuntimeError, "kaput")
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result)

      expect { described_class.call }.to raise_error(described_class::ProviderFailure, /gmail: RuntimeError: kaput/)
    end

    it "declares no inputs" do
      expect(described_class.input_schema).to be_nil
    end
  end

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::EmailsSync")).to eq(described_class)
  end
end
