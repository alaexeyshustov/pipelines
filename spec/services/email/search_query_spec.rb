require "rails_helper"

RSpec.describe Email::SearchQuery do
  let!(:strong) { create(:email, subject: "Interview interview", body: "Interview schedule for next week") }
  let!(:weak) { create(:email, subject: "Hello", body: "Maybe an interview later, plus a long text " * 3) }

  before { create(:email, subject: "Newsletter", body: "Nothing relevant") }

  it "ranks better matches first" do
    expect(described_class.call("interview").map(&:email)).to eq([ strong, weak ])
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
    create(:email, subject: "Offer and terms", body: "x")
    expect(described_class.call("offer AND terms").size).to eq(1)
  end

  describe "mode: :semantic" do
    include EmbeddingHelpers

    let!(:near) { create(:email, subject: "Lease renewal", body: "Your rent contract") }
    let!(:far) { create(:email, subject: "Pizza", body: "Order tonight") }

    before do
      embed_as(near, unit_vector(0))
      embed_as(far, unit_vector(1))
      stub_ollama_embeddings(unit_vector(0))
    end

    it "returns the nearest emails first, with the cosine distance as rank" do
      hits = described_class.call("apartment contract", mode: :semantic)

      expect(hits.map(&:email)).to eq([ near, far ])
      expect(hits.map(&:rank)).to eq([ 0.0, 1.0 ])
      expect(hits.map(&:snippet)).to eq([ nil, nil ])
    end

    it "embeds the query with the Qwen3 instruction prefix" do
      described_class.call("apartment contract", mode: :semantic)
      expect(a_request(:post, EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL).with(
        body: hash_including("input" => [ "Instruct: #{Embeddings::Client::QUERY_INSTRUCTION}\nQuery: apartment contract" ])
      )).to have_been_made
    end

    it "respects the limit" do
      expect(described_class.call("apartment", limit: 1, mode: :semantic).map(&:email)).to eq([ near ])
    end

    it "ignores emails embedded under another model" do
      embed_as(create(:email), unit_vector(0), model: "old-model")
      expect(described_class.call("apartment", mode: :semantic).size).to eq(2)
    end

    it "returns nothing, without calling the model, for a blank query" do
      expect(described_class.call("  ", mode: :semantic)).to eq([])
      expect(a_request(:post, EmbeddingHelpers::OLLAMA_EMBEDDINGS_URL)).not_to have_been_made
    end
  end

  describe "mode: :hybrid" do
    include EmbeddingHelpers

    let!(:both) { create(:email, subject: "Relocation package", body: "schedule") }
    let!(:text_only) { create(:email, subject: "Relocation", body: "relocation relocation relocation") }
    let!(:semantic_only) { create(:email, subject: "Moving house", body: "Please join us") }

    before do
      embed_as(both, unit_vector(0))
      embed_as(semantic_only, unit_vector(1))
      stub_ollama_embeddings(unit_vector(0))
    end

    it "fuses full-text and vector rankings, so a match in both comes first" do
      hits = described_class.call("relocation", mode: :hybrid)

      expect(hits.first.email).to eq(both)
      expect(hits.map(&:email)).to contain_exactly(both, text_only, semantic_only)
    end

    it "keeps snippets from the text match and none for vector-only hits" do
      hits = described_class.call("relocation", mode: :hybrid).index_by(&:email)

      expect(hits[both].snippet).to include("[[Relocation]]")
      expect(hits[semantic_only].snippet).to be_nil
    end

    it "ranks lower for better matches" do
      ranks = described_class.call("relocation", mode: :hybrid).map(&:rank)
      expect(ranks).to eq(ranks.sort)
      expect(ranks).to all(be < 0)
    end

    it "respects the limit" do
      expect(described_class.call("relocation", limit: 2, mode: :hybrid).size).to eq(2)
    end
  end
end
