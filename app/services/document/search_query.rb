# Full-text search over document title and extracted text (FTS5), best match first.
#
#   Document::SearchQuery.call("lease rent").first.snippet  # => "... monthly [[rent]] ..."
#
# User input is turned into quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
#
# With +mode: :semantic+ the query is embedded and the nearest vectors win (see Embeddable.semantic_search); the
# rank is then the cosine distance (lower is better) and there is no snippet. +mode: :hybrid+ fuses both rankings
# (reciprocal rank fusion); its rank is the negated fused score, so lower is still better.
class Document::SearchQuery
  Hit = Data.define(:document, :rank, :snippet)

  def self.call(query, limit: 20, mode: :text)
    new(query, limit:, mode:).call
  end

  def initialize(query, limit:, mode:)
    @query = query
    @limit = limit
    @mode = mode
  end

  def call
    case @mode
    when :semantic then semantic_hits
    when :hybrid then hybrid_hits
    else text_hits
    end
  end

  private

  def text_hits
    Document.fts_search(@query, limit: @limit).map { |m| Hit.new(document: m.record, rank: m.rank, snippet: m.snippet) } # steep:ignore
  end

  def hybrid_hits
    Document.hybrid_search(@query, limit: @limit).map { |h| Hit.new(document: h.record, rank: -h.score, snippet: h.snippet) } # steep:ignore
  end

  def semantic_hits
    Document.semantic_search(@query, limit: @limit).map { |n| Hit.new(document: n.embeddable, rank: n.neighbor_distance, snippet: nil) } # steep:ignore
  end
end
