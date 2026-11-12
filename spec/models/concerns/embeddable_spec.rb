require "rails_helper"

RSpec.describe Embeddable do
  include EmbeddingHelpers

  before { stub_ollama_embeddings(unit_vector(0)) }

  describe ".semantic_search" do
    it "returns the nearest records, nearest first" do
      near = create(:email)
      far = create(:email)
      embed_as(far, unit_vector(1))
      embed_as(near, unit_vector(0))

      expect(Email.semantic_search("q").map(&:embeddable)).to eq([ near, far ])
    end

    it "only returns records inside the relation it is called on" do
      kept = create(:email, subject: "kept")
      other = create(:email, subject: "other")
      [ kept, other ].each { |email| embed_as(email, unit_vector(0)) }

      expect(Email.where(id: kept.id).semantic_search("q").map(&:embeddable)).to eq([ kept ])
    end

    it "skips embeddings whose record no longer exists" do
      orphan = create(:email)
      alive = create(:email)
      [ orphan, alive ].each { |email| embed_as(email, unit_vector(0)) }
      Email.where(id: orphan.id).delete_all

      expect(Email.semantic_search("q").map(&:embeddable)).to eq([ alive ])
    end
  end

  describe ".hybrid_search" do
    it "fuses FTS and vector hits inside the relation and ignores orphaned embeddings" do
      kept = create(:email, body: "salary here")
      other = create(:email, body: "salary there")
      orphan = create(:email, body: "salary gone")
      [ kept, other, orphan ].each { |email| embed_as(email, unit_vector(0)) }
      Email.where(id: orphan.id).delete_all

      expect(Email.where(id: kept.id).hybrid_search("salary").map(&:record)).to eq([ kept ])
      expect(Email.hybrid_search("salary").map(&:record)).to contain_exactly(kept, other)
    end
  end
end
