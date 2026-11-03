require "rails_helper"

RSpec.describe Document do
  def indexed(term)
    described_class.connection.select_values("SELECT rowid FROM documents_fts WHERE documents_fts MATCH '#{term}'")
  end

  describe "validations" do
    it "requires title, mime type, checksum and source" do
      document = described_class.new
      document.validate
      expect(document.errors.attribute_names).to include(:title, :mime_type, :checksum, :source)
    end

    it "limits source to email_attachment and drive" do
      expect(build(:document, source: "dropbox")).not_to be_valid
      expect(build(:document, source: "drive", source_ref: { "provider" => "drive", "drive_file_id" => "f1" })).to be_valid
    end

    it "keeps the checksum unique, in the database too" do
      create(:document, checksum: "abc")
      expect(build(:document, checksum: "abc")).not_to be_valid
      expect { build(:document, checksum: "abc").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a missing extracted text but allows an empty one" do
      expect(build(:document, text: nil)).not_to be_valid
      expect(build(:document, text: "")).to be_valid
    end
  end

  describe "associations" do
    it "optionally belongs to an email and survives its removal" do
      email = create(:email)
      document = create(:document, email:)
      expect(document.email).to eq(email)
      email.destroy!
      expect(document.reload.email).to be_nil
    end

    it "is taggable" do
      document = create(:document)
      tag = create(:tag, name: "finance")
      Tagging.create!(taggable: document, tag:, source: "manual")
      expect(document.tags).to eq([ tag ])
      expect { document.destroy! }.to change(Tagging, :count).by(-1)
    end
  end

  describe ".ingest!" do
    it "does not duplicate a re-ingested file" do
      first = described_class.ingest!(attributes_for(:document, checksum: "same"))
      second = described_class.ingest!(attributes_for(:document, checksum: "same", title: "Other"))
      expect(second).to eq(first)
      expect(described_class.count).to eq(1)
    end
  end

  describe "FTS5 index" do
    it "indexes title and text on insert" do
      document = create(:document, title: "Lease agreement", text: "Monthly rent applies")
      expect(indexed("lease")).to eq([ document.id ])
      expect(indexed("rent")).to eq([ document.id ])
    end

    it "reindexes on update and removes on destroy" do
      document = create(:document, title: "Lease agreement")
      document.update!(title: "Invoice")
      expect(indexed("lease")).to be_empty
      expect(indexed("invoice")).to eq([ document.id ])
      document.destroy!
      expect(indexed("invoice")).to be_empty
    end

    it "stays consistent through bulk writes" do
      create(:document, title: "Lease agreement")
      described_class.update_all(title: "Declined")
      expect(indexed("lease")).to be_empty
      described_class.delete_all
      expect(indexed("declined")).to be_empty
    end
  end
end
