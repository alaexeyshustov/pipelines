# Full-text search over subject, body and sender (FTS5), best match first.
#
#   Email::SearchQuery.call("interview acme").first.snippet  # => "... [[interview]] at ..."
#
# User input is turned into quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
#
# With +mode: :semantic+ the query is embedded and the nearest vectors win (see Embeddable.ranked_search); the
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
    Email.ranked_search(@query, mode: @mode, limit: @limit).map { |hit| Hit.new(email: hit.record, rank: hit.rank, snippet: hit.snippet) } # steep:ignore
  end
end
