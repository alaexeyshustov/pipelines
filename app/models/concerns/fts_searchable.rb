# FTS5 full-text search for models with an external-content "<table>_fts" index (kept in sync by DB triggers).
#
# User input becomes quoted terms (implicitly ANDed), so operators and stray quotes are plain text.
module FtsSearchable
  extend ActiveSupport::Concern

  SCOPE_MARKER = "/*fts_scope*/".freeze
  Match = Data.define(:record, :rank, :snippet)

  class_methods do
    # Best bm25 match first (lower rank is better); snippets mark hits with [[ ]]. Called on a relation
    # (+Email.where(...).fts_search(q)+) it only matches rows inside that relation, and keeps its preloads.
    def fts_search(query, limit: 20)
      match = fts_match(query)
      return [] if match.empty?

      rows = connection.select_rows(fts_statement(match, limit))
      records = unscope(:select).where(id: rows.map(&:first)).index_by(&:id)
      rows.filter_map { |id, rank, snippet| records[id]&.then { |record| Match.new(record:, rank:, snippet:) } } # an index row can outlive its record
    end

    private

    def fts_match(query)
      query.to_s.scrub.unicode_normalize(:nfc).scan(/[\p{L}\p{N}\p{M}_]+/).map { |term| %("#{term}") }.join(" ")
    end

    def fts_statement(match, limit)
      sql = sanitize_sql_array([ fts_sql, match, limit ])
      sql.sub(SCOPE_MARKER) { scope_clause }
    end

    # Restricts matches to the current relation (none when called on the bare class).
    def scope_clause
      return "" unless current_scope

      ids = current_scope.unscope(:order, :limit, :offset, :includes, :preload).reselect(:id)
      "AND #{table_name}.id IN (#{ids.to_sql})"
    end

    def fts_sql
      fts = "#{table_name}_fts"
      <<~SQL
        SELECT #{table_name}.id, bm25(#{fts}) AS rank, snippet(#{fts}, -1, '[[', ']]', '…', 12) AS snippet
        FROM #{fts} JOIN #{table_name} ON #{table_name}.id = #{fts}.rowid
        WHERE #{fts} MATCH ? #{SCOPE_MARKER} ORDER BY rank LIMIT ?
      SQL
    end
  end
end
