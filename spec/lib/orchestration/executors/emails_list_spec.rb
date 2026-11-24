require "rails_helper"

RSpec.describe Orchestration::Executors::EmailsList do
  include ActiveSupport::Testing::TimeHelpers
  include EmbeddingHelpers

  let(:providers) { %w[gmail yahoo] }
  let(:counts) { { "fetched" => 2, "stored" => 2, "duplicates" => 0, "failed" => 0 } }

  before do
    travel_to Time.zone.local(2026, 4, 1, 12)
    allow(Orchestration::Heartbeat).to receive(:beat)
    allow(Rails.logger).to receive(:error)
  end

  def sync_result(mode: "incremental", email_ids: [], counts: self.counts)
    Email::InboxSync::Result.new(mode:, counts:, email_ids:)
  end

  def stub_sync(provider, result = sync_result, date_from: nil, date_to: nil)
    allow(Email::InboxSync).to receive(:call).with(provider:, date_from:, date_to:).and_return(result)
  end

  def execute(**args) = described_class.call(providers:, **args)

  describe "output" do
    it "reports each requested provider's mode and counts, and the new email ids" do
      first = create(:email, provider: "gmail")
      second = create(:email, provider: "yahoo")
      stub_sync("gmail", sync_result(email_ids: [ first.id ]))
      stub_sync("yahoo", sync_result(mode: "window", email_ids: [ second.id ]))

      output = execute

      expect(output["providers"]).to eq(
        "gmail" => counts.merge("mode" => "incremental"),
        "yahoo" => counts.merge("mode" => "window")
      )
      expect(output["email_ids"]).to contain_exactly(first.id, second.id)
    end

    it "reads only the requested providers, one after another in the given order" do
      stub_sync("gmail")
      stub_sync("yahoo")

      described_class.call(providers: %w[yahoo gmail])

      expect(Email::InboxSync).to have_received(:call).with(provider: "yahoo", date_from: nil, date_to: nil).ordered
      expect(Email::InboxSync).to have_received(:call).with(provider: "gmail", date_from: nil, date_to: nil).ordered
    end

    it "does not touch the provider that was not requested" do
      stub_sync("gmail")

      output = described_class.call(providers: %w[gmail])

      expect(output["providers"].keys).to eq(%w[gmail])
      expect(Email::InboxSync).not_to have_received(:call).with(hash_including(provider: "yahoo"))
    end

    it "beats the heartbeat while it works" do
      stub_sync("gmail")
      stub_sync("yahoo")

      execute

      expect(Orchestration::Heartbeat).to have_received(:beat).at_least(:once)
    end
  end

  describe "email_ids" do
    let(:providers) { %w[gmail] }
    let(:new_email) { create(:email, provider: "gmail", classification_status: "pending") }

    before { stub_sync("gmail", sync_result(email_ids: [ new_email.id ])) }


    it "is the unique union of new emails, pending and failed emails of the requested providers, and tagged emails without an embedding" do
      pending_email = create(:email, provider: "gmail", classification_status: "pending")
      failed_email = create(:email, provider: "gmail", classification_status: "failed")
      unembedded = create(:email, provider: "gmail", classification_status: "tagged")

      expect(execute["email_ids"]).to contain_exactly(new_email.id, pending_email.id, failed_email.id, unembedded.id)
    end

    it "lists an id once even when it is new, pending and found by the re-run rules" do
      expect(execute["email_ids"]).to eq([ new_email.id ])
    end

    it "leaves out tagged emails that have an embedding for the current model" do
      embedded = create(:email, provider: "gmail", classification_status: "tagged")
      embed_as(embedded, unit_vector(0))

      expect(execute["email_ids"]).not_to include(embedded.id)
    end

    it "includes a tagged email whose only embedding is for another model" do
      other_model = create(:email, provider: "gmail", classification_status: "tagged")
      embed_as(other_model, unit_vector(0), model: "some-old-model")

      expect(execute["email_ids"]).to include(other_model.id)
    end

    it "leaves out untagged emails" do
      untagged = create(:email, provider: "gmail", classification_status: "untagged")

      expect(execute["email_ids"]).not_to include(untagged.id)
    end

    it "leaves out pending emails of providers that were not requested" do
      other = create(:email, provider: "yahoo", classification_status: "pending")

      expect(execute["email_ids"]).not_to include(other.id)
    end

    it "re-emits tagged emails without an embedding from every provider, including unrequested ones" do
      stub_sync("gmail", sync_result(email_ids: [ new_email.id ]))
      yahoo_tagged = create(:email, provider: "yahoo", classification_status: "tagged")

      output = described_class.call(providers: %w[gmail])

      expect(output["email_ids"]).to include(yahoo_tagged.id)
    end

    it "does not filter by date" do
      old = create(:email, provider: "gmail", classification_status: "pending", date: 3.years.ago)

      expect(execute["email_ids"]).to include(old.id)
    end
  end

  describe "dates" do
    let(:providers) { %w[gmail] }

    it "passes blank dates as nil, whether they are nil or empty strings" do
      stub_sync("gmail")

      execute(date_from: "", date_to: nil)

      expect(Email::InboxSync).to have_received(:call).with(provider: "gmail", date_from: nil, date_to: nil)
    end

    it "passes ISO dates as Date objects" do
      stub_sync("gmail", sync_result(mode: "historical"), date_from: Date.new(2026, 3, 1), date_to: Date.new(2026, 3, 10))

      execute(date_from: "2026-03-01", date_to: "2026-03-10")

      expect(Email::InboxSync).to have_received(:call).with(provider: "gmail", date_from: Date.new(2026, 3, 1), date_to: Date.new(2026, 3, 10))
    end

    it "accepts date_to = today" do
      stub_sync("gmail", date_from: Date.new(2026, 3, 1), date_to: Date.new(2026, 4, 1))

      expect { execute(date_from: "2026-03-01", date_to: "2026-04-01") }.not_to raise_error
    end

    it "accepts date_from = date_to" do
      stub_sync("gmail", date_from: Date.new(2026, 3, 1), date_to: Date.new(2026, 3, 1))

      expect { execute(date_from: "2026-03-01", date_to: "2026-03-01") }.not_to raise_error
    end

    it "computes today in the app time zone" do
      travel_back
      travel_to Time.utc(2026, 3, 31, 20) do
        Time.use_zone("Asia/Tokyo") do # already 2026-04-01 there
          stub_sync("gmail", date_from: Date.new(2026, 4, 1), date_to: nil)

          expect { execute(date_from: "2026-04-01") }.not_to raise_error
        end
      end
    end
  end

  describe "input validation" do
    {
      "no providers" => { providers: [] },
      "nil providers" => { providers: nil },
      "an unknown provider" => { providers: %w[gmail aol] },
      "a malformed date_from" => { date_from: "03/01/2026" },
      "an impossible date_from" => { date_from: "2026-02-30" },
      "a malformed date_to" => { date_from: "2026-03-01", date_to: "tomorrow" },
      "date_from after date_to" => { date_from: "2026-03-10", date_to: "2026-03-01" },
      "a future date_from" => { date_from: "2026-04-02" },
      "a future date_to" => { date_from: "2026-03-01", date_to: "2026-04-02" },
      "date_to without date_from" => { date_to: "2026-03-01" },
      "date_to without date_from (empty string)" => { date_from: "", date_to: "2026-03-01" }
    }.each do |label, args|
      it "raises ArgumentError for #{label}, before reading any provider" do
        allow(Email::InboxSync).to receive(:call)

        expect { described_class.call(providers: %w[gmail], **args) }.to raise_error(ArgumentError)
        expect(Email::InboxSync).not_to have_received(:call)
      end
    end

    it "says which kind of date problem it is, per field", :aggregate_failures do
      expect { described_class.call(providers: %w[gmail], date_from: "03/01/2026") }
        .to raise_error(ArgumentError, "date_from must be a date like 2026-03-31")
      expect { described_class.call(providers: %w[gmail], date_from: "2026-03-01", date_to: "tomorrow") }
        .to raise_error(ArgumentError, "date_to must be a date like 2026-03-31")
      expect { described_class.call(providers: %w[gmail], date_from: "2026-02-30") }
        .to raise_error(ArgumentError, "date_from must be a real date like 2026-03-31")
      expect { described_class.call(providers: %w[gmail], date_from: "2026-03-01", date_to: "2026-13-01") }
        .to raise_error(ArgumentError, "date_to must be a real date like 2026-03-31")
    end

    it "names the offending field in the message" do
      expect { described_class.call(providers: %w[gmail], date_from: "nope") }.to raise_error(ArgumentError, /date_from/)
      expect { described_class.call(providers: %w[aol]) }.to raise_error(ArgumentError, /aol|providers/)
    end
  end

  describe "provider failures" do
    it "reports a provider without credentials as skipped and still reads the other" do
      allow(Email::InboxSync).to receive(:call).with(hash_including(provider: "gmail")).and_raise(Emails::NotConfigured, "no creds")
      stub_sync("yahoo", sync_result(email_ids: [ create(:email, provider: "yahoo").id ]))

      output = execute

      expect(output["providers"]["gmail"]).to include("mode" => "skipped")
      expect(output["providers"]["yahoo"]).to include("mode" => "incremental", "fetched" => 2)
      expect(output["email_ids"]).not_to be_empty
    end

    it "reports any other error per provider with the message and does not fail the step while another provider worked", :aggregate_failures do
      allow(Email::InboxSync).to receive(:call).with(hash_including(provider: "gmail")).and_raise(Google::Apis::ServerError, "gmail down")
      stub_sync("yahoo")

      output = execute

      expect(output["providers"]["gmail"]).to include("error" => /gmail down/, "mode" => "unknown", "fetched" => 0,
                                                      "stored" => 0, "duplicates" => 0, "failed" => 0)
      expect(output["providers"]["yahoo"]).not_to have_key("error")
    end

    it "reports the mode that was attempted when the sync got as far as picking one", :aggregate_failures do
      failure = Email::InboxSync::Failure.new(Google::Apis::ServerError.new("gmail down"), "rescan_window")
      allow(Email::InboxSync).to receive(:call).with(hash_including(provider: "gmail")).and_raise(failure)
      stub_sync("yahoo")

      entry = execute["providers"]["gmail"]

      expect(entry).to include("mode" => "rescan_window", "failed" => 0, "error" => /ServerError: gmail down/)
    end

    it "raises when one provider was skipped and the other failed, since none worked" do
      allow(Email::InboxSync).to receive(:call).with(hash_including(provider: "gmail")).and_raise(Emails::NotConfigured)
      allow(Email::InboxSync).to receive(:call).with(hash_including(provider: "yahoo")).and_raise(RuntimeError, "imap down")

      expect { execute }.to raise_error(StandardError, /imap down/)
    end

    it "raises when every requested provider failed, with the per-provider JSON in the message", :aggregate_failures do
      allow(Email::InboxSync).to receive(:call).and_raise(RuntimeError, "boom")

      expect { execute }.to raise_error(StandardError) do |error|
        expect(error.message).to match(/boom/)
        json = JSON.parse(error.message[/Output: (.*)\z/m, 1])
        expect(json["providers"].keys).to eq(%w[gmail yahoo])
        expect(json["providers"]["gmail"]["error"]).to match(/boom/)
      end
    end

    it "raises when every requested provider was skipped for lack of credentials" do
      allow(Email::InboxSync).to receive(:call).and_raise(Emails::NotConfigured)

      expect { execute }.to raise_error(StandardError, /Output: .*skipped/m)
    end

    it "raises when the only requested provider failed" do
      allow(Email::InboxSync).to receive(:call).and_raise(RuntimeError, "boom")

      expect { described_class.call(providers: %w[yahoo]) }.to raise_error(StandardError, /Output: /)
    end

    it "does not raise when a provider stored mail but some messages failed" do
      stub_sync("gmail", sync_result(counts: counts.merge("failed" => 1)))
      stub_sync("yahoo")

      expect { execute }.not_to raise_error
    end
  end

  describe ".input_schema" do
    subject(:schema) { described_class.input_schema }

    it "declares providers, date_from and date_to, with providers required" do
      expect(schema["properties"].keys).to contain_exactly("providers", "date_from", "date_to")
      expect(schema["required"]).to eq([ "providers" ])
      expect(schema["properties"]["providers"]).to include("type" => "array")
    end

    it "describes the dates and gives them no type, so a nil from an optional mapping passes the schema check" do
      %w[date_from date_to].each do |field|
        expect(schema["properties"][field]).to include("description" => be_present)
        expect(schema["properties"][field]).not_to have_key("type")
      end
    end

    it "accepts nil and empty-string dates in Orchestration::SchemaValidator" do
      validator = Orchestration::SchemaValidator.new(schema)

      expect { validator.validate!({ "providers" => %w[gmail], "date_from" => nil, "date_to" => "" }) }.not_to raise_error
    end
  end

  describe ".output_schema" do
    subject(:schema) { described_class.output_schema }

    it "declares email_ids (integers) and providers, all required", :aggregate_failures do
      expect(schema["type"]).to eq("object")
      expect(schema["properties"]["email_ids"]).to include("type" => "array", "items" => include("type" => "integer"))
      expect(schema["properties"]["providers"]).to include("type" => "object")
      expect(schema["required"]).to contain_exactly("email_ids", "providers")
    end
  end

  describe ".run_hints" do
    def count_queries
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    it "shows the last sync per provider, never for a provider without a cursor" do
      create(:email_sync_cursor, provider: "gmail", last_synced_at: Time.utc(2026, 3, 20, 14, 3, 22))

      expect(described_class.run_hints).to eq("providers" => "Last synced: gmail 2026-03-20 14:03, yahoo never")
    end

    it "uses the latest sync when a provider has several cursors" do
      create(:email_sync_cursor, provider: "yahoo", account: "a@yahoo.com", last_synced_at: Time.utc(2026, 1, 1, 8))
      create(:email_sync_cursor, provider: "yahoo", account: "b@yahoo.com", last_synced_at: Time.utc(2026, 2, 2, 9, 30))

      expect(described_class.run_hints["providers"]).to eq("Last synced: gmail never, yahoo 2026-02-02 09:30")
    end

    it "treats a cursor that never finished a sync as never" do
      create(:email_sync_cursor, provider: "gmail", last_synced_at: nil)

      expect(described_class.run_hints["providers"]).to eq("Last synced: gmail never, yahoo never")
    end

    it "runs one query" do
      create(:email_sync_cursor, provider: "gmail", last_synced_at: Time.utc(2026, 3, 20, 14, 3))

      expect(count_queries { described_class.run_hints }).to eq(1)
    end
  end
end
