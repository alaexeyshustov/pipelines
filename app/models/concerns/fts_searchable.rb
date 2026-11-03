# FTS5 full-text search for models with an external-content "<table>_fts" index (kept in sync by DB triggers).
#
# User input becomes quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
module FtsSearchable
  extend ActiveSupport::Concern

  Match = Data.define(:record, :rank, :snippet)

  class_methods do
    # Best bm25 match first (lower rank is better); snippets mark hits with [[ ]].
    def fts_search(query, limit: 20)
      match = fts_match(query)
      return [] if match.empty?

      rows = connection.select_rows(sanitize_sql_array([ fts_sql, match, limit ]))
      records = where(id: rows.map(&:first)).index_by(&:id)
      rows.map { |id, rank, snippet| Match.new(record: records.fetch(id), rank: rank, snippet: snippet) }
    end

    private

    def fts_match(query)
      query.to_s.scan(/[[:alnum:]_]+/).map { |term| %("#{term}") }.join(" ")
    end

    def fts_sql
      fts = "#{table_name}_fts"
      <<~SQL
        SELECT #{table_name}.id, bm25(#{fts}) AS rank, snippet(#{fts}, -1, '[[', ']]', '…', 12) AS snippet
        FROM #{fts} JOIN #{table_name} ON #{table_name}.id = #{fts}.rowid
        WHERE #{fts} MATCH ? ORDER BY rank LIMIT ?
      SQL
    end
  end
end
