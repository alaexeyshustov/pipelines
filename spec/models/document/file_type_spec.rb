require "rails_helper"

RSpec.describe Document::FileType do
  describe ".resolve" do
    it "keeps a specific type" do
      expect(described_class.resolve("application/pdf", "cv.docx")).to eq("application/pdf")
    end

    it "infers a generic or blank type from the filename" do
      expect(described_class.resolve("application/octet-stream", "cv.PDF")).to eq("application/pdf")
      expect(described_class.resolve(nil, "a.docx")).to eq(Document::FileType::DOCX)
    end

    it "keeps the generic type when the filename says nothing" do
      expect(described_class.resolve("application/octet-stream", "blob")).to eq("application/octet-stream")
    end
  end

  describe ".supported?" do
    it "accepts pdf, docx, plain text and images only" do
      supported = [ "application/pdf", Document::FileType::DOCX, "text/plain", "image/jpeg" ]
      expect(supported.map { |type| described_class.supported?(type) }).to all(be(true))
      expect([ "application/zip", "application/octet-stream", nil ].map { |type| described_class.supported?(type) }).to all(be(false))
    end
  end
end
