# Full-text search over subject, body and sender (FTS5), best match first.
#
#   Email::SearchQuery.call("interview acme").first.snippet  # => "... [[interview]] at ..."
#
# User input is turned into quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
#
# With +mode: :semantic+ the query is embedded and the nearest vectors win (see Embeddable.semantic_search); the
# rank is then the cosine distance (lower is better) and there is no snippet. +mode: :hybrid+ fuses both rankings
# (reciprocal rank fusion); its rank is the negated fused score, so lower is still better.
class Email::SearchQuery
  Hit = Data.define(:email, :rank, :snippet)

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
    Email.fts_search(@query, limit: @limit).map { |m| Hit.new(email: m.record, rank: m.rank, snippet: m.snippet) } # steep:ignore
  end

  def hybrid_hits
    Email.hybrid_search(@query, limit: @limit).map { |h| Hit.new(email: h.record, rank: -h.score, snippet: h.snippet) } # steep:ignore
  end

  def semantic_hits
    Email.semantic_search(@query, limit: @limit).map { |n| Hit.new(email: n.embeddable, rank: n.distance, snippet: nil) } # steep:ignore
  end
end
