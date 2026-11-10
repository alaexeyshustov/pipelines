require "rails_helper"

RSpec.describe Document::DetectDuplicates do
  include EmbeddingHelpers

  # Unit vector at +index+ blended with +index+ + 1 so that cosine similarity to unit_vector(index) is exactly +similarity+.
  def vector_at(index, similarity)
    vector = unit_vector(index).map { |value| value * similarity }
    vector[index + 1] = Math.sqrt(1 - (similarity**2))
    vector
  end

  let(:document) { create(:document) }

  before { embed_as(document, unit_vector(0)) }

  it "flags a document whose vector is above the threshold" do
    other = create(:document)
    embed_as(other, vector_at(0, 0.97))

    result = described_class.call(document)

    expect(result.flagged).to eq(1)
    flagged = DocumentDuplicate.includes(:document, :duplicate).sole
    expect(flagged).to have_attributes(document: document, duplicate: other, status: "pending")
    expect(flagged.similarity).to be_within(0.001).of(0.97)
  end

  it "flags several neighbours without a query per neighbour" do
    others = create_list(:document, 4).each { |other| embed_as(other, vector_at(0, 0.97)) }

    expect(described_class.call(document).flagged).to eq(others.size)
    expect(DocumentDuplicate.count).to eq(others.size)
  end

  it "keeps dismissed pairs and refreshes pending ones when flagging several neighbours" do
    dismissed = create(:document).tap { |other| embed_as(other, vector_at(0, 0.97)) }
    pending = create(:document).tap { |other| embed_as(other, vector_at(0, 0.98)) }
    DocumentDuplicate.flag!(document, dismissed, similarity: 0.5).dismissed!
    DocumentDuplicate.flag!(document, pending, similarity: 0.5)

    described_class.call(document)

    pairs = DocumentDuplicate.includes(:document, :duplicate).index_by { |pair| pair.other(document) }
    expect(pairs[dismissed]).to have_attributes(status: "dismissed", similarity: 0.5)
    expect(pairs[pending].similarity).to be_within(0.001).of(0.98)
  end

  it "ignores documents below the threshold, itself and other models" do
    embed_as(create(:document), vector_at(0, 0.90))
    embed_as(create(:document), vector_at(0, 0.99), model: "other-model")

    expect(described_class.call(document).flagged).to eq(0)
    expect(DocumentDuplicate.count).to eq(0)
  end

  it "skips embeddings of Documents that no longer exist" do
    orphan = create(:document)
    embed_as(orphan, vector_at(0, 0.99))
    Document.where(id: orphan.id).delete_all

    expect(described_class.call(document).flagged).to eq(0)
  end

  it "ignores emails" do
    embed_as(create(:email), vector_at(0, 0.99))

    expect(described_class.call(document).flagged).to eq(0)
  end

  it "does nothing for a document that is not embedded yet" do
    expect(described_class.call(create(:document)).flagged).to eq(0)
  end

  it "is idempotent" do
    embed_as(create(:document), vector_at(0, 0.97))
    described_class.call(document)

    expect { described_class.call(document) }.not_to change(DocumentDuplicate, :count)
  end

  it "does not re-flag a dismissed pair" do
    other = create(:document)
    embed_as(other, vector_at(0, 0.97))
    described_class.call(document)
    DocumentDuplicate.sole.dismissed!

    described_class.call(other)

    expect(DocumentDuplicate.sole.status).to eq("dismissed")
  end

  describe "threshold" do
    let!(:other) { create(:document).tap { |record| embed_as(record, vector_at(0, 0.97)) } }

    it "defaults to 0.95" do
      expect(described_class.threshold).to eq(0.95)
    end

    it "reads the Setting before ENV" do
      Setting.set("document_dedup_threshold", "0.99")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("DOCUMENT_DEDUP_THRESHOLD", anything).and_return("0.5")

      expect(described_class.threshold).to eq(0.99)
      expect(described_class.call(document).flagged).to eq(0)
    end

    it "falls back to ENV" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("DOCUMENT_DEDUP_THRESHOLD", anything).and_return("0.99")

      expect(described_class.threshold).to eq(0.99)
    end

    it "flags at a lowered threshold" do
      embed_as(other, vector_at(0, 0.90))
      Setting.set("document_dedup_threshold", "0.85")

      expect(described_class.call(document).flagged).to eq(1)
    end
  end
end
