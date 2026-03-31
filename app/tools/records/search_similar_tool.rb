module Records
  class SearchSimilarTool < RubyLLM::Tool
    include ModelResolver

    description "Search a database column for values similar to a given string. " \
                "Matches on substrings in both directions and word-level edit distance. " \
                "Useful for finding variant spellings of company names or job titles before normalizing."

    param :table,  type: :string, desc: "Table name: application_mails or interviews", required: true
    param :column, type: :string, desc: "Column to search (e.g. 'company', 'job_title')",  required: true
    param :value,  type: :string, desc: "Value to find similar matches for", required: true

    def name = "search_similar"

    def execute(table:, column:, value:)
      model = resolve_model(table)
      return { error: "Unknown column #{column}" } unless model::COLUMN_NAMES.include?(column)

      substring_matches = fetch_substring_matches(model, column, value)
      fuzzy_matches     = fetch_fuzzy_matches(model, column, value)

      merged = (substring_matches + fuzzy_matches)
                 .group_by { |match| match[:value] }
                 .map { |val, entries| { value: val, ids: entries.flat_map { |entry| entry[:ids] }.uniq.sort } }
                 .sort_by { |match| match[:value] }

      { matches: merged }
    rescue ModelNotFound => error
      { error: error.message }
    end

    private

    # SQL: stored value contains query OR query contains stored value.
    def fetch_substring_matches(model, column, value)
      conn   = model.connection
      quoted = conn.quote_column_name(column)
      sql    = <<~SQL
        SELECT #{quoted}, GROUP_CONCAT(id) AS ids
        FROM #{model.table_name}
        WHERE #{quoted} IS NOT NULL AND #{quoted} != ''
          AND (#{quoted} LIKE :like OR :value LIKE '%' || #{quoted} || '%')
        GROUP BY #{quoted}
        ORDER BY #{quoted}
      SQL

      conn.select_all(
        model.sanitize_sql([ sql, { value: value, like: "%#{value}%" } ])
      ).map do |row|
        { value: row[column], ids: row["ids"].to_s.split(",").map(&:to_i) }
      end
    end

    # Ruby-side: word-level Levenshtein — catches typos like "Softwear" → "Software".
    def fetch_fuzzy_matches(model, column, value)
      matcher = FuzzyMatcher.new(value)

      model.where.not(column => [ nil, "" ]).pluck(:id, column)
        .group_by { |_id, stored| stored }
        .filter_map do |stored, pairs|
          next unless matcher.matches?(stored)

          { value: stored, ids: pairs.map(&:first).sort }
        end
    end
  end
end
