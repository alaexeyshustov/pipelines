require "rails_helper"

RSpec.describe Document::IngestEmailAttachments do
  include ActiveJob::TestHelper
  include EmailAdapterHelpers

  let(:email) { create(:email, provider: "gmail", provider_message_id: "m1", source_url: "https://mail.google.com/#inbox/m1") }
  let(:listing) do
    [ { id: "a1", filename: "cv.pdf", mime_type: "application/pdf", size: 10 },
      { id: "a2", filename: "notes.zip", mime_type: "application/zip", size: 10 } ]
  end
  let(:bytes) { { "a1" => "%PDF-one", "a2" => "zip" } }
  let(:adapter) { stub_gmail_adapter }
  let(:ocr_url) { "https://api.mistral.ai/v1/ocr" }

  def stub_ocr(markdown = "extracted text")
    stub_request(:post, ocr_url).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { model: "mistral-ocr-latest", pages: [ { "index" => 0, "markdown" => markdown } ] }.to_json
    )
  end

  before do
    allow(adapter).to receive(:attachments).with("m1").and_return(listing)
    allow(adapter).to receive(:attachment) { |_message_id, attachment_id| bytes.fetch(attachment_id) }
    stub_ocr
  end

  after { Emails.configure }

  describe "a new attachment" do
    it "stores a pending Document with the OCR text, linked to the email, and returns its id", :aggregate_failures do
      result = described_class.call(email)
      document = Document.sole

      expect(result).to have_attributes(document_ids: [ document.id ], failed: be_empty)
      expect(document).to have_attributes(
        title: "cv.pdf", text: "extracted text", mime_type: "application/pdf", source: "email_attachment",
        email_id: email.id, source_url: email.source_url, classification_status: "pending",
        checksum: Digest::SHA256.hexdigest("%PDF-one"),
        source_ref: { "provider" => "gmail", "message_id" => "m1", "attachment_id" => "a1" }
      )
      expect(a_request(:post, ocr_url)).to have_been_made.once
    end

    it "infers the type of an application/octet-stream attachment from its filename" do
      allow(adapter).to receive(:attachments).with("m1")
        .and_return([ { id: "a1", filename: "cv.pdf", mime_type: "application/octet-stream", size: 10 },
                      { id: "a2", filename: "blob.bin", mime_type: "application/octet-stream", size: 10 } ])

      result = described_class.call(email)

      expect(result.document_ids.size).to eq(1)
      expect(Document.sole).to have_attributes(title: "cv.pdf", mime_type: "application/pdf")
    end

    it "queues no embedding or tagging itself: the pipeline steps do that" do
      expect { described_class.call(email) }.not_to have_enqueued_job
    end

    it "returns empty lists for an email without attachments" do
      allow(adapter).to receive(:attachments).with("m1").and_return([])

      expect(described_class.call(email)).to have_attributes(document_ids: [], failed: [])
    end
  end

  describe "a Yahoo email" do
    let(:email) { create(:email, provider: "yahoo", provider_message_id: "77:101", source_url: nil) }
    let(:yahoo) do
      stub_yahoo_adapter(
        attachments: [ { id: "2", filename: "cv.pdf", mime_type: "application/pdf", size: 10 },
                       { id: "3", filename: "notes.zip", mime_type: "application/zip", size: 10 } ],
        attachment: "%PDF-yahoo"
      )
    end

    before { yahoo }

    it "stores a Document whose source_ref carries the id, the IMAP part path and the provider", :aggregate_failures do
      result = described_class.call(email)
      document = Document.sole

      expect(result).to have_attributes(document_ids: [ document.id ], failed: be_empty)
      expect(document).to have_attributes(
        title: "cv.pdf", source: "email_attachment", email_id: email.id, mime_type: "application/pdf",
        checksum: Digest::SHA256.hexdigest("%PDF-yahoo"),
        source_ref: { "provider" => "yahoo", "message_id" => "77:101", "attachment_id" => "2" }
      )
    end

    it "downloads only the supported attachment" do
      described_class.call(email)

      expect(yahoo).to have_received(:attachment).with("77:101", "2")
      expect(yahoo).not_to have_received(:attachment).with("77:101", "3")
    end
  end

  describe "unsupported attachment types" do
    it "ignores them silently: not downloaded, not listed as failed" do
      result = described_class.call(email)

      expect(adapter).not_to have_received(:attachment).with("m1", "a2")
      expect(result.failed).to be_empty
    end
  end

  describe "an attachment whose bytes are already a Document" do
    let!(:known) { create(:document, checksum: Digest::SHA256.hexdigest("%PDF-one"), source: "drive") }

    it "skips the OCR, creates nothing, and still returns the existing Document's id" do
      result = nil

      expect { result = described_class.call(email) }.not_to change(Document, :count)

      expect(result.document_ids).to eq([ known.id ])
      expect(a_request(:post, ocr_url)).not_to have_been_made
    end

    it "keeps the first email as the owner when the same attachment arrives on a second email" do
      other = create(:email, provider: "gmail", provider_message_id: "m2")
      allow(adapter).to receive(:attachments).with("m2").and_return([ listing.first.merge(id: "b1") ])
      bytes["b1"] = "%PDF-one"

      expect(described_class.call(other).document_ids).to eq([ known.id ])
    end
  end

  it "beats the heartbeat once per supported attachment" do
    allow(Orchestration::Heartbeat).to receive(:beat)

    described_class.call(email)

    expect(Orchestration::Heartbeat).to have_received(:beat).once # a2 (zip) is unsupported
  end

  describe "a failing attachment" do
    let(:listing) do
      [ { id: "a1", filename: "cv.pdf", mime_type: "application/pdf", size: 10 },
        { id: "a3", filename: "b.png", mime_type: "image/png", size: 1 } ]
    end
    let(:bytes) { { "a1" => "%PDF-one", "a3" => "png" } }

    before do
      stub_request(:post, ocr_url).to_return do |request|
        if JSON.parse(request.body).dig("document", "type") == "document_url"
          { status: 500, headers: { "Content-Type" => "application/json" }, body: { message: "ocr down" }.to_json }
        else
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: { model: "mistral-ocr-latest", pages: [ { "index" => 0, "markdown" => "png text" } ] }.to_json }
        end
      end
    end

    it "is reported in failed with its filename while the other attachments continue", :aggregate_failures do
      result = described_class.call(email)

      expect(Document.pluck(:title)).to eq([ "b.png" ])
      expect(result.document_ids).to eq([ Document.sole.id ])
      expect(result.failed.size).to eq(1)
      expect(result.failed.to_s).to include("cv.pdf")
    end

    it "includes the error class in the entry" do
      expect(described_class.call(email).failed.to_s).to match(/cv\.pdf.*Error/)
    end
  end

  describe "a download that fails" do
    it "is reported in failed, not raised" do
      allow(adapter).to receive(:attachment).with("m1", "a1").and_raise(Google::Apis::ServerError.new("boom"))

      result = described_class.call(email)

      expect(result.document_ids).to be_empty
      expect(result.failed.to_s).to match(/cv\.pdf.*ServerError.*boom/)
    end
  end
end
