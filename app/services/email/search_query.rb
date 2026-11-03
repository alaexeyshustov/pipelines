# Full-text search over subject, body and sender (FTS5), best match first.
#
#   Email::SearchQuery.call("interview acme").first.snippet  # => "... [[interview]] at ..."
#
# User input is turned into quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
class Email::SearchQuery
  Hit = Data.define(:email, :rank, :snippet)

  SQL = <<~SQL.freeze
    SELECT emails.id, bm25(emails_fts) AS rank,
           snippet(emails_fts, -1, '[[', ']]', '…', 12) AS snippet
    FROM emails_fts JOIN emails ON emails.id = emails_fts.rowid
    WHERE emails_fts MATCH ?
    ORDER BY rank LIMIT ?
  SQL

  def self.call(query, limit: 20)
    new(query, limit:).call
  end

  def initialize(query, limit:)
    @query = query.to_s
    @limit = limit
  end

  def call
    match = match_expression
    return [] if match.empty?

    rows = Email.connection.select_rows(Email.sanitize_sql_array([ SQL, match, @limit ])) # steep:ignore
    emails = Email.where(id: rows.map(&:first)).index_by(&:id) # steep:ignore
    rows.map { |id, rank, snippet| Hit.new(email: emails.fetch(id), rank: rank, snippet: snippet) }
  end

  private

  def match_expression
    @query.scan(/[[:alnum:]_]+/).map { |term| %("#{term}") }.join(" ")
  end
end
