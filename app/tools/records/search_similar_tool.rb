module Records
  class SearchSimilarTool < RubyLLM::Tool
    include ModelResolver

    def self.readonly? = true

    description "Search a database column for values similar to a given string. " \
                "Matches on substrings in both directions and word-level edit distance. " \
                "Useful for finding variant spellings of company names or job titles before normalizing."

    param :table,  type: :string, desc: "Table name: application_mails or interviews", required: true
    param :column, type: :string, desc: "Column to search (e.g. 'company', 'job_title')",  required: true
    param :value,  type: :string, desc: "Value to find similar matches for", required: true

    def name = "search_similar"

    def execute(table:, column:, value:)
      model = resolve_model(table)
      return { error: "Unknown column #{column}" } unless model.tool_column_names.include?(column)

      { matches: merged_matches(model, column, value) }
    rescue ModelNotFound => error
      { error: error.message }
    end

    private

    def merged_matches(model, column, value)
      (fetch_substring_matches(model, column, value) + fetch_fuzzy_matches(model, column, value))
        .group_by { |match| match[:value] }
        .map { |val, entries| { value: val, ids: entries.flat_map { |entry| entry[:ids] }.uniq.sort } }
        .sort_by { |match| match[:value] } #: Array[Hash[Symbol, String | Array[Integer]]]
    end

    # SQL: stored value contains query OR query contains stored value.
    def fetch_substring_matches(model, column, value)
      conn   = model.connection
      quoted = conn.quote_column_name(column)
      sql    = build_substring_sql(quoted, model.table_name)

      conn.select_all(model.sanitize_sql([ sql, { value: value, like: "%#{value}%" } ]))
          .filter_map { |row| map_substring_row(row, column) }
    end

    def build_substring_sql(quoted, table_name)
      <<~SQL
        SELECT #{quoted}, GROUP_CONCAT(id) AS ids
        FROM #{table_name}
        WHERE #{quoted} IS NOT NULL AND #{quoted} != ''
          AND (#{quoted} LIKE :like OR :value LIKE '%' || #{quoted} || '%')
        GROUP BY #{quoted}
        ORDER BY #{quoted}
      SQL
    end

    def map_substring_row(row, column)
      match_value = row[column]
      return unless match_value

      { value: match_value, ids: row["ids"].to_s.split(",").map(&:to_i) }
    end

    # Ruby-side: word-level Levenshtein — catches typos like "Softwear" → "Software".
    def fetch_fuzzy_matches(model, column, value)
      matcher = FuzzyMatcher.new(value)
      quoted_column = model.connection.quote_column_name(column)

      model.where("#{quoted_column} IS NOT NULL AND #{quoted_column} != ''").pluck(:id, column) #: Array[[Integer, String]]
        .group_by { |_id, stored| stored }
        .filter_map do |stored, pairs|
          next unless matcher.matches?(stored)

          { value: stored, ids: pairs.map(&:first).sort }
        end
    end
  end
end
