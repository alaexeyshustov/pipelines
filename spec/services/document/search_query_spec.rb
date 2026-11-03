require "rails_helper"

RSpec.describe Document::SearchQuery do
  let!(:strong) { create(:document, title: "Interview interview", text: "Interview schedule for next week") }
  let!(:weak) { create(:document, title: "Hello", text: "Maybe an interview later, plus a long text " * 3) }

  before { create(:document, title: "Newsletter", text: "Nothing relevant") }

  it "ranks better matches first" do
    expect(described_class.call("interview").map(&:document)).to eq([ strong, weak ])
  end

  it "returns snippets with highlight markers" do
    hit = described_class.call("schedule").first
    expect(hit.snippet).to include("[[schedule]]")
  end

  it "exposes a bm25 rank where lower is better" do
    first, second = described_class.call("interview")
    expect(first.rank).to be < second.rank
  end

  it "respects the limit" do
    expect(described_class.call("interview", limit: 1).size).to eq(1)
  end

  it "returns nothing for blank queries" do
    expect(described_class.call("  ")).to eq([])
    expect(described_class.call(nil)).to eq([])
  end

  it "does not raise on quotes and FTS operators" do
    [ %q("unbalanced), "foo AND", "NOT", "a OR (b", "x*", "col:val", "-", %q(it's) ].each do |q|
      expect { described_class.call(q) }.not_to raise_error
    end
  end

  it "treats operator words as plain terms" do
    create(:document, title: "Offer and terms", text: "x")
    expect(described_class.call("offer AND terms").size).to eq(1)
  end

  describe "mode: :semantic" do
    include EmbeddingHelpers

    it "returns the nearest documents first, not the emails" do
      near = create(:document, title: "Lease.pdf")
      far = create(:document, title: "Menu.pdf")
      embed_as(near, unit_vector(0))
      embed_as(far, unit_vector(1))
      embed_as(create(:email), unit_vector(0))
      stub_ollama_embeddings(unit_vector(0))

      hits = described_class.call("rent agreement", mode: :semantic)

      expect(hits.map(&:document)).to eq([ near, far ])
      expect(hits.first.rank).to eq(0.0)
    end
  end

  describe "mode: :hybrid" do
    include EmbeddingHelpers

    it "fuses full-text and vector rankings, so a match in both comes first" do
      both = create(:document, title: "Relocation policy", text: "schedule")
      text_only = create(:document, title: "Relocation", text: "relocation relocation")
      semantic_only = create(:document, title: "Moving guide", text: "boxes")
      embed_as(both, unit_vector(0))
      embed_as(semantic_only, unit_vector(1))
      stub_ollama_embeddings(unit_vector(0))

      hits = described_class.call("relocation", mode: :hybrid)

      expect(hits.first.document).to eq(both)
      expect(hits.map(&:document)).to contain_exactly(both, text_only, semantic_only)
    end
  end
end
