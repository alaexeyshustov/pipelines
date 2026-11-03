require "rails_helper"

RSpec.describe Embedding do
  def unit(index) = Array.new(Embeddings::Client::DIMENSIONS) { |i| i == index ? 1.0 : 0.0 }

  def vector_ids
    described_class.connection.select_values("SELECT rowid FROM embedding_vectors").map(&:to_i)
  end

  def store(record, vector, model: "m1", digest: "d1")
    described_class.store!(record, model:, content_digest: digest, vector:)
  end

  describe "#vector" do
    it "reads the stored vector back" do
      embedding = store(create(:document), unit(3))

      expect(embedding.vector).to eq(unit(3))
    end
  end

  describe ".store!" do
    it "records model, dimensions, digest and time, and indexes the vector" do
      email = create(:email)
      embedding = store(email, unit(0))

      expect(embedding).to have_attributes(embeddable: email, model: "m1", dimensions: 1024, content_digest: "d1")
      expect(embedding.embedded_at).to be_within(5.seconds).of(Time.current)
      expect(vector_ids).to eq([ embedding.id ])
    end

    it "replaces the vector and digest of the same item and model" do
      email = create(:email)
      first = store(email, unit(0))
      second = store(email, unit(1), digest: "d2")

      expect([ second.id, second.content_digest, vector_ids ]).to eq([ first.id, "d2", [ first.id ] ])
      expect(described_class.nearest(unit(1), type: "Email", model: "m1").map(&:distance)).to eq([ 0.0 ])
    end

    it "keeps one embedding per model" do
      email = create(:email)
      store(email, unit(0), model: "m1")
      store(email, unit(0), model: "m2")
      expect(email.embeddings.pluck(:model)).to contain_exactly("m1", "m2")
    end

    it "rejects a vector of the wrong size" do
      expect { store(create(:email), [ 0.1 ]) }.to raise_error(ArgumentError, /1024/)
    end
  end

  describe ".nearest" do
    it "returns the nearest items first with their cosine distance" do
      near = create(:email)
      far = create(:email)
      store(far, unit(1))
      store(near, unit(0).tap { |v| v[1] = 0.2 })

      hits = described_class.nearest(unit(0), type: "Email", model: "m1")
      expect(hits.map(&:embeddable)).to eq([ near, far ])
      expect(hits.map(&:distance)).to match([ be_within(0.05).of(0.02), be_within(0.001).of(1.0) ])
    end

    it "only considers the given type and model" do
      email = create(:email)
      document = create(:document)
      other_model = create(:email)
      store(email, unit(0))
      store(document, unit(0))
      store(other_model, unit(0), model: "m2")

      expect(described_class.nearest(unit(0), type: "Email", model: "m1").map(&:embeddable)).to eq([ email ])
    end

    it "honours the limit" do
      3.times { |i| store(create(:email), unit(i)) }
      expect(described_class.nearest(unit(0), type: "Email", model: "m1", limit: 2).size).to eq(2)
    end
  end

  describe "#destroy" do
    it "removes the vector, and the item's destruction removes its embeddings" do
      email = create(:email)
      store(email, unit(0))
      email.destroy!
      expect(vector_ids).to be_empty
      expect(described_class.count).to eq(0)
    end
  end

  describe ".purge_except!" do
    it "drops the embeddings and vectors of every other model" do
      email = create(:email)
      store(email, unit(0), model: "old")
      kept = store(email, unit(0), model: "new")

      described_class.purge_except!("new")

      expect(described_class.all).to eq([ kept ])
      expect(vector_ids).to eq([ kept.id ])
    end
  end
end
