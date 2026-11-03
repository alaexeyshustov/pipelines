# Records that get a vector per embedding model (see +Embedding+); the vectors are removed with the record.
module Embeddable
  extend ActiveSupport::Concern

  Hybrid = Data.define(:record, :score, :snippet)

  included do
    has_many :embeddings, as: :embeddable, dependent: :destroy
  end

  class_methods do
    # The +limit+ records nearest in meaning to +query+ under the configured embedding model, nearest first, as
    # Embedding::Neighbor (+distance+ is cosine distance, 0 = same direction). Embeds the query with one model call.
    def semantic_search(query, limit: 20)
      return [] if query.blank?

      model = LlmModels.embedding
      Embedding.nearest(Embeddings::Client.query(query.to_s, model:), type: polymorphic_name, model:, limit:)
    end

    # FTS5 matches (FtsSearchable) and semantic neighbours fused by reciprocal rank (Embeddings::RankFusion), best first.
    # +score+ is the fused score (higher is better); +snippet+ comes from the FTS match, nil for vector-only hits.
    def hybrid_search(query, limit: 20)
      matches = fts_search(query, limit:).index_by { |match| match.record.id }
      neighbours = semantic_search(query, limit:).index_by { |neighbour| neighbour.embeddable.id }
      fuse(matches, neighbours).first(limit)
    end

    private

    def fuse(matches, neighbours)
      Embeddings::RankFusion.call(matches.keys, neighbours.keys).map { |id, score| fused_hit(score, matches[id], neighbours[id]) }
    end

    def fused_hit(score, match, neighbour)
      Hybrid.new(record: match ? match.record : neighbour.embeddable, score:, snippet: match&.snippet)
    end
  end
end
