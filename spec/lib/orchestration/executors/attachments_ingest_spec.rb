require "rails_helper"

RSpec.describe Orchestration::Executors::AttachmentsIngest do
  let(:results) { {} }

  before do
    allow(Orchestration::Heartbeat).to receive(:beat)
    allow(Document::IngestEmailAttachments).to receive(:call) do |email|
      result = results.fetch(email.id)
      result.respond_to?(:call) ? result.call : result
    end
  end

  def ingest_result(document_ids: [], failed: [])
    Document::IngestEmailAttachments::Result.new(document_ids:, failed:)
  end

  def execute(*emails) = described_class.call(email_ids: emails.map(&:id))

  def gmail_email(status = "tagged") = create(:email, provider: "gmail", classification_status: status)

  it "ingests the attachments of tagged Gmail emails and returns the document ids" do
    email = gmail_email
    document = create(:document, email: nil)
    results[email.id] = ingest_result(document_ids: [ document.id ])

    expect(execute(email)).to eq("document_ids" => [ document.id ], "skipped" => [], "failed" => [])
    expect(Document::IngestEmailAttachments).to have_received(:call).with(email)
  end

  it "returns the documents an earlier run left, whatever their status, so they reach steps 5 and 6" do
    email = gmail_email
    documents = %w[failed pending tagged].map { |status| create(:document, email:, classification_status: status) }

    expect(execute(email)["document_ids"]).to match_array(documents.map(&:id))
  end

  it "does not download again a tagged email that already has documents, but still returns them" do
    email = gmail_email
    leftover = create(:document, email:, classification_status: "failed")

    output = execute(email)

    expect(Document::IngestEmailAttachments).not_to have_received(:call)
    expect(output).to eq("document_ids" => [ leftover.id ], "skipped" => [], "failed" => [])
  end

  it "ingests the emails without documents among a mix of re-listed and new ones" do
    done = gmail_email
    fresh = gmail_email
    old_doc = create(:document, email: done)
    new_doc = create(:document, email: nil, source: "drive")
    results[fresh.id] = ingest_result(document_ids: [ new_doc.id ])

    output = execute(done, fresh)

    expect(Document::IngestEmailAttachments).to have_received(:call).once.with(fresh)
    expect(output["document_ids"]).to contain_exactly(old_doc.id, new_doc.id)
  end

  it "includes a document found by checksum, which the service now returns" do
    email = gmail_email
    known = create(:document, email: nil, source: "drive")
    results[email.id] = ingest_result(document_ids: [ known.id ])

    expect(execute(email)["document_ids"]).to eq([ known.id ])
  end

  it "lists every id once, across emails" do
    first = gmail_email
    second = gmail_email
    shared = create(:document, email: nil)
    results[first.id] = ingest_result(document_ids: [ shared.id ])
    results[second.id] = ingest_result(document_ids: [ shared.id ])

    expect(execute(first, second)["document_ids"]).to eq([ shared.id ])
  end

  it "skips Yahoo emails without calling the service, even when tagged, and does not return their documents" do
    yahoo = create(:email, provider: "yahoo", classification_status: "tagged")
    create(:document, email: yahoo)

    output = execute(yahoo)

    expect(output).to eq("document_ids" => [], "skipped" => [ yahoo.id ], "failed" => [])
    expect(Document::IngestEmailAttachments).not_to have_received(:call)
  end

  %w[pending untagged failed].each do |status|
    it "skips a #{status} Gmail email" do
      email = gmail_email(status)

      expect(execute(email)).to include("skipped" => [ email.id ], "document_ids" => [])
      expect(Document::IngestEmailAttachments).not_to have_received(:call)
    end
  end

  it "reports a failed attachment as the email's failure with the service's message, and keeps the documents that worked" do
    email = gmail_email
    document = create(:document, email: nil)
    results[email.id] = ingest_result(document_ids: [ document.id ], failed: [ "cv.pdf: RuntimeError: ocr down" ])

    output = execute(email)

    expect(output["failed"]).to eq([ { "id" => email.id, "error" => "cv.pdf: RuntimeError: ocr down" } ])
    expect(output["document_ids"]).to eq([ document.id ])
  end

  it "records an exception from one email as failed and goes on with the rest" do
    bad = gmail_email
    good = gmail_email
    document = create(:document, email: nil)
    allow(Document::IngestEmailAttachments).to receive(:call) do |email|
      email.id == bad.id ? raise(Google::Apis::ServerError, "gmail down") : ingest_result(document_ids: [ document.id ])
    end

    output = execute(bad, good)

    expect(output["document_ids"]).to eq([ document.id ])
    expect(output["failed"]).to contain_exactly("id" => bad.id, "error" => a_string_including("ServerError", "gmail down"))
  end

  it "beats the heartbeat per email" do
    emails = [ gmail_email, gmail_email ]
    emails.each { |email| results[email.id] = ingest_result }

    execute(*emails)

    expect(Orchestration::Heartbeat).to have_received(:beat).at_least(:twice)
  end

  it "handles an id once even when it is repeated" do
    email = gmail_email
    results[email.id] = ingest_result

    described_class.call(email_ids: [ email.id, email.id ])

    expect(Document::IngestEmailAttachments).to have_received(:call).once
  end

  it "declares email_ids as its required input and document_ids, skipped and failed as outputs" do
    expect(described_class.input_schema["required"]).to eq([ "email_ids" ])
    schema = described_class.output_schema
    expect(schema["required"]).to contain_exactly("document_ids", "skipped", "failed")
    expect(schema["properties"]["document_ids"]).to include("type" => "array", "items" => include("type" => "integer"))
  end

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::AttachmentsIngest")).to eq(described_class)
  end
end
