# Records that get a vector per embedding model (see +Embedding+); the vectors are removed with the record. The
# including model defines +embedding_parts+, the strings (title, body, ...) Embeddings::Text joins into the embedded text.
module Embeddable
  extend ActiveSupport::Concern

  Hybrid = Data.define(:record, :score, :snippet)
  Ranked = Data.define(:record, :rank, :snippet)

  included do
    has_many :embeddings, as: :embeddable, dependent: :destroy
  end

  class_methods do
    # The +limit+ records nearest in meaning to +query+ under the configured embedding model, nearest first, as
    # Embeddings (+neighbor_distance+ is cosine distance, 0 = same direction). Embeds the query with one model call.
    # Called on a relation (+Email.where(...).semantic_search(q)+) it only considers records inside that relation;
    # embeddings of deleted records are never returned.
    def semantic_search(query, limit: 20)
      return [] if query.blank?

      model = LlmModels.embedding
      Embedding.nearest(Embeddings::Client.query(query.to_s, model:), type: polymorphic_name, model:, scope: all, limit:)
    end

    # FTS5 matches (FtsSearchable) and semantic neighbours fused by reciprocal rank (Neighbor::Reranking.rrf), best first.
    # +score+ is the fused score (higher is better); +snippet+ comes from the FTS match, nil for vector-only hits.
    def hybrid_search(query, limit: 20)
      matches = fts_search(query, limit:).index_by { |match| match.record.id }
      neighbours = semantic_search(query, limit:).index_by { |neighbour| neighbour.embeddable.id }
      fuse(matches, neighbours).first(limit)
    end

    # One search API over the three modes, best first, with lower +rank+ always better: +:text+ ranks by bm25
    # (fts_search), +:semantic+ by cosine distance with no snippet, +:hybrid+ by the negated fused score.
    # Raises ArgumentError for any other mode.
    def ranked_search(query, mode: :text, limit: 20)
      case mode
      when :text then text_ranked(query, limit)
      when :semantic then semantic_ranked(query, limit)
      when :hybrid then hybrid_ranked(query, limit)
      else raise ArgumentError, "Unknown search mode: #{mode.inspect}"
      end
    end

    private

    def text_ranked(query, limit)
      fts_search(query, limit:).map { |m| Ranked.new(record: m.record, rank: m.rank, snippet: m.snippet) }
    end

    def semantic_ranked(query, limit)
      semantic_search(query, limit:).map { |n| Ranked.new(record: n.embeddable, rank: n.neighbor_distance, snippet: nil) }
    end

    def hybrid_ranked(query, limit)
      hybrid_search(query, limit:).map { |h| Ranked.new(record: h.record, rank: -h.score, snippet: h.snippet) }
    end

    def fuse(matches, neighbours)
      Neighbor::Reranking.rrf(matches.keys, neighbours.keys).map { |hit| fused_hit(hit[:score], matches[hit[:result]], neighbours[hit[:result]]) }
    end

    def fused_hit(score, match, neighbour)
      Hybrid.new(record: match ? match.record : neighbour.embeddable, score:, snippet: match&.snippet)
    end
  end
end
