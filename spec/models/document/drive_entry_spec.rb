require "rails_helper"

RSpec.describe Document::DriveEntry do
  subject(:drive_entry) { described_class.new(entry) }

  let(:entry) do
    Emails::Adapters::DriveFileFetcher::Entry.new(id: "f1", name: "notes.pdf", mime_type: "application/pdf", md5: md5,
                                                  modified_time: "2026-01-01T00:00:00Z", web_view_link: "https://drive/f1")
  end
  let(:md5) { "abc" }

  describe "#mime_type" do
    it "exports Google Docs as docx" do
      google_doc = entry.with(mime_type: Emails::Adapters::DriveFileFetcher::GOOGLE_DOC_MIME)

      expect(described_class.new(google_doc).mime_type).to eq(Document::FileType::DOCX)
    end
  end

  describe "#unchanged?" do
    it "compares Drive's md5" do
      expect(drive_entry.unchanged?(Document.new(source_ref: { "md5" => "abc" }))).to be(true)
    end

    context "when the file has no md5" do
      let(:md5) { nil }

      it "compares modifiedTime" do
        expect(drive_entry.unchanged?(Document.new(source_ref: { "modified_time" => "2026-01-02T00:00:00Z" }))).to be(false)
      end
    end
  end

  describe "#relink_attributes" do
    it "points the Document at this file" do
      expect(drive_entry.relink_attributes).to include(title: "notes.pdf", source_url: "https://drive/f1",
                                                       source_ref: hash_including(drive_file_id: "f1", md5: "abc"))
    end
  end
end
