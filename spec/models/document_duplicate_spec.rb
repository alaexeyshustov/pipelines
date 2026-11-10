require "rails_helper"

RSpec.describe DocumentDuplicate do
  let!(:older) { create(:document) }
  let!(:newer) { create(:document) }

  describe ".flag!" do
    it "records a pending pair in canonical order whichever way it is given" do
      duplicate = described_class.flag!(newer, older, similarity: 0.97)

      expect(duplicate).to have_attributes(document: older, duplicate: newer, similarity: 0.97, status: "pending")
    end

    it "is idempotent and refreshes the similarity of a pending pair" do
      described_class.flag!(older, newer, similarity: 0.96)

      expect { described_class.flag!(newer, older, similarity: 0.98) }.not_to change(described_class, :count)
      expect(described_class.sole.similarity).to eq(0.98)
    end

    it "keeps a dismissed pair dismissed" do
      described_class.flag!(older, newer, similarity: 0.96).dismissed!

      described_class.flag!(older, newer, similarity: 0.99)

      expect(described_class.sole).to have_attributes(status: "dismissed", similarity: 0.96)
    end

    it "rejects a document paired with itself" do
      expect { described_class.flag!(older, older, similarity: 1.0) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#other" do
    it "returns the document on the other side of the pair" do
      duplicate = described_class.flag!(older, newer, similarity: 0.97)

      expect([ duplicate.other(older), duplicate.other(newer) ]).to eq([ newer, older ])
    end
  end

  describe ".involving" do
    it "finds pairs on either side" do
      first = described_class.flag!(older, newer, similarity: 0.97)
      second = described_class.flag!(create(:document), newer, similarity: 0.96)

      expect(described_class.involving(newer)).to contain_exactly(first, second)
      expect(described_class.involving(older)).to contain_exactly(first)
    end
  end

  it "is removed with either document" do
    described_class.flag!(older, newer, similarity: 0.97)

    expect { newer.destroy! }.to change(described_class, :count).by(-1)
  end

  describe ".threshold" do
    it "defaults to 0.95" do
      expect(described_class.threshold).to eq(0.95)
    end

    it "reads the Setting before ENV" do
      Setting.set("document_dedup_threshold", "0.99")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("DOCUMENT_DEDUP_THRESHOLD", anything).and_return("0.5")

      expect(described_class.threshold).to eq(0.99)
    end

    it "falls back to ENV" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("DOCUMENT_DEDUP_THRESHOLD", anything).and_return("0.99")

      expect(described_class.threshold).to eq(0.99)
    end
  end
end
