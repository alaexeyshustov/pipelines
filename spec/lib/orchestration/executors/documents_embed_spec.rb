require "rails_helper"

RSpec.describe Orchestration::Executors::DocumentsEmbed do
  include EmbeddingHelpers

  let(:embed_calls) { [] }
  let(:embed_outcome) { ->(_records) { Embeddings::Embed::Result.new(embedded: 1, unchanged: 0, skipped: 0) } }
  let(:flagged) { Hash.new(0) }

  before do
    allow(Orchestration::Heartbeat).to receive(:beat)
    allow(Embeddings::Embed).to receive(:call) do |records, **|
      embed_calls << records
      embed_outcome.call(records)
    end
    allow(Document::DetectDuplicates).to receive(:call) { |document, **| Document::DetectDuplicates::Result.new(flagged: flagged[document.id]) }
  end

  def execute(*documents) = described_class.call(document_ids: documents.map(&:id))

  it "embeds tagged documents without an embedding, per record, then runs duplicate detection for each", :aggregate_failures do
    first = create(:document, classification_status: "tagged")
    second = create(:document, classification_status: "tagged")
    flagged[first.id] = 2
    flagged[second.id] = 1

    output = execute(first, second)

    expect(output).to eq("embedded" => [ first.id, second.id ], "skipped" => [], "duplicates_found" => 3, "failed" => [])
    expect(embed_calls).to contain_exactly([ first ], [ second ])
    expect(Document::DetectDuplicates).to have_received(:call).with(first, any_args)
    expect(Document::DetectDuplicates).to have_received(:call).with(second, any_args)
  end

  it "reports duplicates_found as a count, 0 when nothing was flagged" do
    document = create(:document, classification_status: "tagged")

    expect(execute(document)["duplicates_found"]).to eq(0)
  end

  %w[pending untagged failed].each do |status|
    it "lists a #{status} document as skipped: no embedding, no duplicate detection" do
      document = create(:document, classification_status: status)

      output = execute(document)

      expect(output).to eq("embedded" => [], "skipped" => [ document.id ], "duplicates_found" => 0, "failed" => [])
      expect(embed_calls).to be_empty
      expect(Document::DetectDuplicates).not_to have_received(:call)
    end
  end

  it "does not embed or run duplicate detection for a document that already has an embedding" do
    document = create(:document, classification_status: "tagged")
    embed_as(document, unit_vector(0))

    expect(execute(document)).to include("embedded" => [], "skipped" => [])
    expect(embed_calls).to be_empty
    expect(Document::DetectDuplicates).not_to have_received(:call)
  end

  it "lists a document that had no text to embed as skipped, without duplicate detection" do
    document = create(:document, classification_status: "tagged", text: "")
    allow(Embeddings::Embed).to receive(:call).and_return(Embeddings::Embed::Result.new(embedded: 0, unchanged: 0, skipped: 1))

    expect(execute(document)).to include("embedded" => [], "skipped" => [ document.id ])
    expect(Document::DetectDuplicates).not_to have_received(:call)
  end

  context "when the model call fails for one document" do
    let(:embed_outcome) do
      lambda do |records|
        raise RubyLLM::ConnectionError, "ollama down" if records.first.title == "broken.pdf"

        Embeddings::Embed::Result.new(embedded: 1, unchanged: 0, skipped: 0)
      end
    end

    it "records it as failed, skips its duplicate detection, and goes on" do
      broken = create(:document, classification_status: "tagged", title: "broken.pdf")
      fine = create(:document, classification_status: "tagged")

      output = execute(broken, fine)

      expect(output["embedded"]).to eq([ fine.id ])
      expect(output["failed"]).to contain_exactly("id" => broken.id, "error" => a_string_including("ConnectionError", "ollama down"))
      expect(Document::DetectDuplicates).not_to have_received(:call).with(broken, any_args)
    end
  end

  context "when duplicate detection fails after the document was embedded" do
    let!(:first) { create(:document, classification_status: "tagged") }
    let!(:second) { create(:document, classification_status: "tagged") }

    before do
      allow(Document::DetectDuplicates).to receive(:call).with(anything, any_args).and_raise(ActiveRecord::StatementInvalid, "db locked")
    end

    it "keeps the documents embedded and reports each one in failed, and goes on", :aggregate_failures do
      output = execute(first, second)

      expect(output).to include("embedded" => [ first.id, second.id ], "duplicates_found" => 0)
      expect(output["failed"]).to contain_exactly(
        { "id" => first.id, "error" => a_string_including("StatementInvalid", "db locked") },
        { "id" => second.id, "error" => a_string_including("StatementInvalid", "db locked") }
      )
    end

    it "enqueues Document::DetectDuplicatesJob for each as the fallback" do
      expect { execute(first, second) }
        .to have_enqueued_job(Document::DetectDuplicatesJob).with(first.id)
        .and have_enqueued_job(Document::DetectDuplicatesJob).with(second.id)
    end
  end

  it "handles an id once even when it is repeated" do
    document = create(:document, classification_status: "tagged")

    described_class.call(document_ids: [ document.id, document.id ])

    expect(embed_calls.size).to eq(1)
  end

  it "beats the heartbeat per record" do
    documents = create_list(:document, 2, classification_status: "tagged")

    execute(*documents)

    expect(Orchestration::Heartbeat).to have_received(:beat).at_least(:twice)
  end

  it "declares document_ids as its required input and embedded, skipped, duplicates_found and failed as outputs" do
    expect(described_class.input_schema["required"]).to eq([ "document_ids" ])
    schema = described_class.output_schema
    expect(schema["required"]).to contain_exactly("embedded", "skipped", "duplicates_found", "failed")
    expect(schema["properties"]["duplicates_found"]).to include("type" => "integer")
  end

  it "is registered as a pipeline service" do
    expect(Orchestration::ServiceRegistry.lookup("Orchestration::Executors::DocumentsEmbed")).to eq(described_class)
  end
end
