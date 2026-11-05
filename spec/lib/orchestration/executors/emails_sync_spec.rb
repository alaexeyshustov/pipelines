require "rails_helper"

RSpec.describe Orchestration::Executors::EmailsSync do
  include ActiveJob::TestHelper

  def sync_result(mode: "incremental", fetched: 2, stored: 1, duplicates: 1, failed: 0, email_ids: [])
    counts = { "mode" => mode, "fetched" => fetched, "stored" => stored, "duplicates" => duplicates, "failed" => failed }
    Email::SyncInboxJob::Result.new(counts: counts, email_ids: email_ids)
  end

  describe ".call" do
    it "syncs gmail and yahoo inline and reports the counts per provider, with nothing enqueued when nothing is new or stale" do
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result(stored: 1))
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result(mode: "backfill", fetched: 3, stored: 3, duplicates: 0))

      expect(described_class.call).to eq(
        "documents_requeued" => 0,
        "gmail" => { "mode" => "incremental", "fetched" => 2, "stored" => 1, "duplicates" => 1, "failed" => 0, "enqueued" => 0, "requeued" => 0 },
        "yahoo" => { "mode" => "backfill", "fetched" => 3, "stored" => 3, "duplicates" => 0, "failed" => 0, "enqueued" => 0, "requeued" => 0 }
      )
    end

    describe "processing the emails" do
      let(:new_email) { create(:email, provider: "gmail") }
      let(:other_new_email) { create(:email, provider: "gmail") }

      before do
        allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result(stored: 0))
      end

      it "enqueues Email::ProcessJob for each newly stored email and reports the count" do
        allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail")
          .and_return(sync_result(stored: 2, email_ids: [ new_email.id, other_new_email.id ]))

        output = nil
        expect { output = described_class.call }
          .to have_enqueued_job(Email::ProcessJob).with(new_email.id)
          .and have_enqueued_job(Email::ProcessJob).with(other_new_email.id)
        expect(output.fetch("gmail")).to include("enqueued" => 2, "requeued" => 0)
      end

      it "enqueues nothing for duplicates" do
        allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail")
          .and_return(sync_result(stored: 0, duplicates: 2, email_ids: []))

        expect { described_class.call }.not_to have_enqueued_job(Email::ProcessJob)
      end

      it "re-enqueues an email whose earlier tagging failed on the next run" do
        failed = create(:email, provider: "gmail", created_at: 3.hours.ago)
        allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result(stored: 0))
        allow(Tags::Classifier).to receive(:call).and_raise(RubyLLM::Error, "down")
        Email::ProcessJob.perform_now(failed.id)

        expect { described_class.call }.to have_enqueued_job(Email::ProcessJob).with(failed.id)
      end
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

  describe "requeueing untagged emails" do
    let!(:stale) { create(:email, provider: "gmail", created_at: 2.hours.ago, tagged_at: nil) }
    let!(:stale_yahoo) { create(:email, provider: "yahoo", created_at: 2.hours.ago, tagged_at: nil) }

    before do
      create(:email, provider: "gmail", created_at: 2.hours.ago, tagged_at: 1.hour.ago)
      create(:email, provider: "gmail", created_at: 10.minutes.ago, tagged_at: nil)
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result(stored: 0))
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result(stored: 0))
    end

    it "re-enqueues those older than an hour, per provider" do
      expect { described_class.call }
        .to have_enqueued_job(Email::ProcessJob).with(stale.id).exactly(:once)
        .and have_enqueued_job(Email::ProcessJob).with(stale_yahoo.id).exactly(:once)
      expect(enqueued_jobs.count { |job| job["job_class"] == "Email::ProcessJob" }).to eq(2)
    end

    it "counts them as requeued and as enqueued" do
      expect(described_class.call.fetch("gmail")).to include("enqueued" => 1, "requeued" => 1)
    end
  end

  describe "requeueing untagged attachment Documents" do
    let!(:email) { create(:email, provider: "gmail") }
    let!(:stale) { create(:document, email: email, created_at: 2.hours.ago, tagged_at: nil) }

    before do
      create(:document, email: email, created_at: 2.hours.ago, tagged_at: 1.hour.ago)
      create(:document, email: email, created_at: 10.minutes.ago, tagged_at: nil)
      create(:document, source: "drive", source_ref: { "drive_file_id" => "f1" }, created_at: 2.hours.ago, tagged_at: nil)
      allow(Email::SyncInboxJob).to receive(:perform_now).with("gmail").and_return(sync_result(stored: 0))
      allow(Email::SyncInboxJob).to receive(:perform_now).with("yahoo").and_return(sync_result(stored: 0))
    end

    it "re-enqueues Document::TagJob once for the stale untagged email attachments, not for Drive Documents" do
      expect { described_class.call }.to have_enqueued_job(Document::TagJob).with(stale.id).exactly(:once)
      expect(enqueued_jobs.count { |job| job["job_class"] == "Document::TagJob" }).to eq(1)
    end

    it "reports them as one top-level documents_requeued" do
      expect(described_class.call).to include("documents_requeued" => 1)
    end
  end

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::EmailsSync")).to eq(described_class)
  end
end
