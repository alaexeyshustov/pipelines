# Full-text search over document title and extracted text (FTS5), best match first.
#
#   Document::SearchQuery.call("lease rent").first.snippet  # => "... monthly [[rent]] ..."
#
# User input is turned into quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
class Document::SearchQuery
  Hit = Data.define(:document, :rank, :snippet)

  def self.call(query, limit: 20)
    new(query, limit:).call
  end

  def initialize(query, limit:)
    @query = query
    @limit = limit
  end

  def call
    Document.fts_search(@query, limit: @limit).map { |m| Hit.new(document: m.record, rank: m.rank, snippet: m.snippet) } # steep:ignore
  end
end
