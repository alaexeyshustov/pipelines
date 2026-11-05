require "rails_helper"

RSpec.describe Document::ExtractEmailAttachmentsJob do
  include ActiveJob::TestHelper

  let(:email) { create(:email, provider: "gmail", provider_message_id: "m1", source_url: "https://mail.google.com/#inbox/m1") }
  let(:attachments) do
    [ { id: "a1", filename: "cv.pdf", mime_type: "application/pdf", size: 10 },
      { id: "a2", filename: "notes.zip", mime_type: "application/zip", size: 10 } ]
  end
  let(:bytes) { { "a1" => "%PDF-one", "a2" => "zip" } }

  before do
    create(:tag, name: "job_application")
    allow(Emails).to receive(:attachments).with("gmail", "m1").and_return(attachments)
    allow(Emails).to receive(:attachment) { |_provider, _msg, id| bytes.fetch(id) }
    allow(Document::TextExtractor).to receive(:call).and_return("extracted")
  end

  context "with a tagged email" do
    before { create(:tagging, taggable: email, tag: Tag.first) }

    it "creates a Document per supported attachment, linked to the email, and queues its tagging" do
      expect { described_class.perform_now(email.id) }.to change(Document, :count).by(1)

      doc = Document.last
      expect(doc).to have_attributes(
        title: "cv.pdf", text: "extracted", mime_type: "application/pdf", source: "email_attachment",
        email_id: email.id, source_url: email.source_url,
        checksum: Digest::SHA256.hexdigest("%PDF-one"),
        source_ref: { "provider" => "gmail", "message_id" => "m1", "attachment_id" => "a1" }
      )
      expect(Document::TagJob).to have_been_enqueued.with(doc.id)
    end

    it "queues the embedding before the tagging, so a tagging failure cannot lose it" do
      described_class.perform_now(email.id)
      classes = enqueued_jobs.pluck("job_class")
      expect(classes.index("Document::EmbedJob")).to be < classes.index("Document::TagJob")
    end

    it "enqueues the embedding of the new Document, once for a repeated attachment" do
      expect { described_class.perform_now(email.id) }.to have_enqueued_job(Document::EmbedJob)
      expect { described_class.perform_now(email.id) }.not_to have_enqueued_job(Document::EmbedJob)
    end

    it "yields one Document when the same attachment arrives on two emails" do
      other = create(:email, provider: "gmail", provider_message_id: "m2")
      create(:tagging, taggable: other, tag: Tag.first)
      allow(Emails).to receive(:attachments).with("gmail", "m2").and_return([ attachments.first.merge(id: "b1") ])
      bytes["b1"] = "%PDF-one"

      described_class.perform_now(email.id)
      expect { described_class.perform_now(other.id) }.not_to change(Document, :count)
    end

    it "logs a failing attachment and still processes the others" do
      attachments << { id: "a3", filename: "b.png", mime_type: "image/png", size: 1 }
      bytes["a3"] = "png"
      allow(Document::TextExtractor).to receive(:call) do |filename:, **|
        filename == "cv.pdf" ? raise(RubyLLM::Error, "ocr down") : "png text"
      end
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(email.id)

      expect(Document.pluck(:title)).to eq([ "b.png" ])
      expect(Rails.logger).to have_received(:error).with(/cv\.pdf.*ocr down/)
    end

    it "skips emails from providers without attachment support" do
      yahoo = create(:email, provider: "yahoo")
      create(:tagging, taggable: yahoo, tag: Tag.first)
      expect { described_class.perform_now(yahoo.id) }.not_to change(Document, :count)
    end
  end

  it "skips untagged emails" do
    expect { described_class.perform_now(email.id) }.not_to change(Document, :count)
    expect(Emails).not_to have_received(:attachments)
  end
end
