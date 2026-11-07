require "rails_helper"

RSpec.describe Document::SyncDriveJob do
  include ActiveJob::TestHelper

  let(:fetcher) { Emails::Adapters::DriveFileFetcher.new(access_token: -> { "tok" }) }
  let(:pdf_entry) { entry("f1", "cv.pdf", "application/pdf", md5: "md5-1") }
  let(:gdoc_entry) { entry("g1", "Notes", Emails::Adapters::DriveFileFetcher::GOOGLE_DOC_MIME, modified_time: "2026-02-01T00:00:00.000Z") }
  let(:entries) { [ pdf_entry, gdoc_entry ] }
  let(:empty_folders) { [] }
  let(:docx) { Document::TextExtractor::DOCX }

  def entry(id, name, mime_type, md5: nil, modified_time: "2026-01-01T00:00:00.000Z")
    Emails::Adapters::DriveFileFetcher::Entry.new(
      id:, name:, mime_type:, md5:, modified_time:, web_view_link: "https://drive.google.com/file/d/#{id}/view"
    )
  end

  def drive_file(data, name, mime_type)
    Emails::Adapters::DriveFileFetcher::File.new(data:, filename: name, mime_type:)
  end

  def drive_document(drive_file_id, md5: nil, modified_time: "2026-01-01T00:00:00.000Z", **attrs)
    create(:document, source: "drive", **attrs, source_ref: {
      "provider" => "drive", "drive_file_id" => drive_file_id, "md5" => md5, "modified_time" => modified_time
    })
  end

  before do
    Setting.set("drive_folder_ids", "root1, https://drive.google.com/drive/folders/root2?usp=sharing")
    allow(Emails::Adapters::DriveFileFetcher).to receive(:from_env).and_return(fetcher)
    allow(fetcher).to receive(:scan).with(%w[root1 root2]) { entries }
    allow(fetcher).to receive(:empty_folders).with(%w[root1 root2]) { empty_folders }
    allow(fetcher).to receive(:fetch).with("f1").and_return(drive_file("%PDF", "cv.pdf", "application/pdf"))
    allow(fetcher).to receive(:fetch).with("g1").and_return(drive_file("docx-bytes", "Notes", docx))
    allow(Document::TextExtractor).to receive(:call).and_return("extracted")
  end

  it "creates a Document per supported file with Drive source data and extracted text" do
    expect { described_class.perform_now }.to change(Document, :count).by(2)

    expect(Document.find_by(title: "cv.pdf")).to have_attributes(
      text: "extracted", mime_type: "application/pdf", source: "drive", checksum: Digest::SHA256.hexdigest("%PDF"),
      email_id: nil, source_url: "https://drive.google.com/file/d/f1/view",
      source_ref: { "provider" => "drive", "drive_file_id" => "f1", "md5" => "md5-1",
                    "modified_time" => "2026-01-01T00:00:00.000Z" }
    )
  end

  it "exports Google Docs as docx through the extractor" do
    described_class.perform_now

    expect(Document.find_by(title: "Notes")).to have_attributes(mime_type: docx, checksum: Digest::SHA256.hexdigest("docx-bytes"))
    expect(Document::TextExtractor).to have_received(:call).with(data: "docx-bytes", mime_type: docx, filename: "Notes")
  end

  it "queues the tagging of each new Document" do
    expect { described_class.perform_now }.to have_enqueued_job(Document::TagJob).exactly(2).times
  end

  it "leaves new Documents untagged until Document::TagJob succeeds" do
    described_class.perform_now

    expect(Document.where(source: "drive").pluck(:tagged_at)).to all(be_nil)
  end

  it "enqueues the embedding of each new Document" do
    expect { described_class.perform_now }.to have_enqueued_job(Document::EmbedJob).exactly(2).times
  end

  it "enqueues the embedding of a changed Document, and none for unchanged ones" do
    existing = drive_document("f1", md5: "stale-md5", text: "old")
    drive_document("g1", modified_time: "2026-02-01T00:00:00.000Z")

    expect { described_class.perform_now }.to have_enqueued_job(Document::EmbedJob).with(existing.id).once
  end

  context "when files are unchanged" do
    before do
      drive_document("f1", md5: "md5-1")
      drive_document("g1", modified_time: "2026-02-01T00:00:00.000Z")
    end

    it "does not fetch or extract them again (md5 for files, modifiedTime for Google Docs)" do
      expect { described_class.perform_now }.not_to change(Document, :count)

      expect(fetcher).not_to have_received(:fetch)
      expect(Document::TextExtractor).not_to have_received(:call)
    end

    it "does not tag them again" do
      expect { described_class.perform_now }.not_to have_enqueued_job(Document::TagJob)
    end
  end

  describe "retrying the tagging of unchanged Documents" do
    let!(:stale) { drive_document("f1", md5: "md5-1", created_at: 2.hours.ago, tagged_at: nil) }

    before do
      drive_document("g1", modified_time: "2026-02-01T00:00:00.000Z", created_at: 2.hours.ago, tagged_at: 1.hour.ago)
    end

    it "queues Document::TagJob for an untagged one that is older than REQUEUE_AFTER" do
      expect { described_class.perform_now }.to have_enqueued_job(Document::TagJob).with(stale.id).once
    end

    it "does not queue Documents that were stored recently" do
      stale.update!(created_at: 5.minutes.ago)
      expect { described_class.perform_now }.not_to have_enqueued_job(Document::TagJob)
    end

    it "counts them as requeued" do
      expect(described_class.perform_now).to include("requeued" => 1, "unchanged" => 2)
    end
  end

  it "re-extracts a changed file in place" do
    existing = drive_document("f1", md5: "stale-md5", text: "old")
    drive_document("g1", modified_time: "2026-02-01T00:00:00.000Z")

    expect { described_class.perform_now }.not_to change(Document, :count)

    expect(existing.reload).to have_attributes(
      text: "extracted", checksum: Digest::SHA256.hexdigest("%PDF"), source_ref: hash_including("md5" => "md5-1")
    )
  end

  it "clears tagged_at of a changed file and queues it for tagging again" do
    existing = drive_document("f1", md5: "stale-md5", tagged_at: 1.day.ago)
    drive_document("g1", modified_time: "2026-02-01T00:00:00.000Z", tagged_at: 1.day.ago)

    expect { described_class.perform_now }.to have_enqueued_job(Document::TagJob).with(existing.id).once
    expect(existing.reload.tagged_at).to be_nil
  end

  it "deletes Documents of Drive files that are gone, leaving other sources alone" do
    gone = drive_document("old")
    attachment = create(:document)
    entries.clear

    expect { described_class.perform_now }.to change(Document, :count).by(-1)

    expect(Document.exists?(gone.id)).to be(false)
    expect(Document.exists?(attachment.id)).to be(true)
  end

  context "when a whitelisted folder lists nothing (revoked or mistyped id)" do
    let(:empty_folders) { [ "root2" ] }
    let!(:gone) { drive_document("old") }

    before { allow(Rails.logger).to receive(:warn) }

    it "deletes no Documents, as an empty listing is not an error" do
      entries.clear

      expect { described_class.perform_now }.not_to change(Document, :count)
      expect(Document.exists?(gone.id)).to be(true)
    end

    it "still syncs the files of the other folders and reports the empty folder" do
      summary = described_class.perform_now

      expect(summary).to include("created" => 2, "deleted" => 0, "empty_folders" => 1)
      expect(Rails.logger).to have_received(:warn).with(/root2/)
    end
  end

  it "does not extract a file whose bytes already exist as a Document from another source" do
    attachment = create(:document, checksum: Digest::SHA256.hexdigest("%PDF"))
    entries.replace([ pdf_entry ])

    expect { described_class.perform_now }.not_to change(Document, :count)

    expect(Document::TextExtractor).not_to have_received(:call)
    expect(attachment.reload.source).to eq("email_attachment")
  end

  context "when a changed file's new bytes match another Document" do
    let!(:stale) { drive_document("f1", md5: "stale-md5", text: "old") }
    let!(:other) { create(:document, checksum: Digest::SHA256.hexdigest("%PDF")) }

    before { entries.replace([ pdf_entry ]) }

    it "destroys the stale Drive Document and keeps the other one" do
      expect { described_class.perform_now }.to change(Document, :count).by(-1)

      expect(Document.exists?(stale.id)).to be(false)
      expect(other.reload.source).to eq("email_attachment")
    end

    it "counts it as merged, not failed, and does not extract it" do
      summary = described_class.perform_now

      expect(summary).to include("merged" => 1, "failed" => 0, "updated" => 0)
      expect(Document::TextExtractor).not_to have_received(:call)
    end

    it "queues no embedding or tagging for it" do
      expect { described_class.perform_now }.not_to have_enqueued_job(Document::TagJob)
    end

    it "is stable on the next scan, where the file has no Document of its own" do
      described_class.perform_now

      expect(described_class.perform_now).to include("merged" => 0, "failed" => 0, "created" => 0)
    end
  end

  it "skips unsupported file types without fetching them" do
    entries << entry("z1", "a.zip", "application/zip", md5: "md5-z")

    described_class.perform_now

    expect(fetcher).not_to have_received(:fetch).with("z1")
    expect(Document.where(source: "drive").count).to eq(2)
  end

  it "logs a failing file, keeps its existing Document and processes the rest" do
    existing = drive_document("f1", md5: "stale", checksum: "stale")
    allow(Document::TextExtractor).to receive(:call) do |filename:, **|
      filename == "cv.pdf" ? raise(RubyLLM::Error, "ocr down") : "ok"
    end
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(Rails.logger).to have_received(:error).with(/cv\.pdf.*ocr down/)
    expect(existing.reload.checksum).to eq("stale")
    expect(Document.exists?(title: "Notes")).to be(true)
  end

  it "does nothing when no folders are whitelisted" do
    Setting.set("drive_folder_ids", " , ")
    keep = drive_document("f1")

    described_class.perform_now

    expect(fetcher).not_to have_received(:scan)
    expect(Document.exists?(keep.id)).to be(true)
  end

  it "deletes nothing when the scan fails" do
    keep = drive_document("f1")
    allow(fetcher).to receive(:scan).and_raise(Emails::Adapters::DriveFileFetcher::Error, "Drive request failed (500)")

    expect { described_class.perform_now }.to raise_error(Emails::Adapters::DriveFileFetcher::Error)
    expect(Document.exists?(keep.id)).to be(true)
  end

  it "returns a summary of what changed" do
    drive_document("old")
    expect(described_class.perform_now).to eq(
      { "created" => 2, "updated" => 0, "unchanged" => 0, "deleted" => 1, "failed" => 0, "requeued" => 0, "empty_folders" => 0, "merged" => 0 }
    )
  end
end
