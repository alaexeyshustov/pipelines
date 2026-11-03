# Full-text search over subject, body and sender (FTS5), best match first.
#
#   Email::SearchQuery.call("interview acme").first.snippet  # => "... [[interview]] at ..."
#
# User input is turned into quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
class Email::SearchQuery
  Hit = Data.define(:email, :rank, :snippet)

  def self.call(query, limit: 20)
    new(query, limit:).call
  end

  def initialize(query, limit:)
    @query = query
    @limit = limit
  end

  def call
    Email.fts_search(@query, limit: @limit).map { |m| Hit.new(email: m.record, rank: m.rank, snippet: m.snippet) } # steep:ignore
  end
end
