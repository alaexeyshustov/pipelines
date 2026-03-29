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
                 .group_by { |m| m[:value] }
                 .map { |val, entries| { value: val, ids: entries.flat_map { |e| e[:ids] }.uniq.sort } }
                 .sort_by { |m| m[:value] }

      { matches: merged }
    rescue ModelNotFound => e
      { error: e.message }
    end

    private

    # SQL: stored value contains query OR query contains stored value.
    def fetch_substring_matches(model, column, value)
      quoted = model.connection.quote_column_name(column)
      sql    = <<~SQL
        SELECT #{quoted}, GROUP_CONCAT(id) AS ids
        FROM #{model.table_name}
        WHERE #{quoted} IS NOT NULL AND #{quoted} != ''
          AND (#{quoted} LIKE :like OR :value LIKE '%' || #{quoted} || '%')
        GROUP BY #{quoted}
        ORDER BY #{quoted}
      SQL

      model.connection.select_all(
        model.sanitize_sql([ sql, { value: value, like: "%#{value}%" } ])
      ).map do |row|
        { value: row[column], ids: row["ids"].to_s.split(",").map(&:to_i) }
      end
    end

    # Ruby-side: word-level Levenshtein — catches typos like "Softwear" → "Software".
    # Fetches all distinct non-null values and keeps those where the majority of
    # query words closely match a word in the stored value.
    def fetch_fuzzy_matches(model, column, value)
      query_words = normalize_words(value)
      return [] if query_words.empty?

      model.where.not(column => [ nil, "" ]).pluck(:id, column)
        .group_by { |_id, stored| stored }
        .filter_map do |stored, pairs|
          stored_words = normalize_words(stored)
          matched = query_words.count { |qw| stored_words.any? { |sw| words_similar?(qw, sw) } }
          next unless matched.to_f / query_words.size >= 0.5

          { value: stored, ids: pairs.map(&:first).sort }
        end
    end

    def normalize_words(str)
      str.downcase.gsub(/[^a-z0-9\s]/, " ").split
    end

    # Two words are similar if they share the same first letter and their
    # Levenshtein distance is ≤ 2 (handles one-or-two character typos).
    def words_similar?(a, b)
      return true  if a == b
      return false if a[0] != b[0]

      levenshtein(a, b) <= 2
    end

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      prev = (0..b.length).to_a
      a.each_char.with_index(1) do |ca, i|
        curr = [ i ]
        b.each_char.with_index(1) do |cb, j|
          curr << (ca == cb ? prev[j - 1] : 1 + [ prev[j], curr.last, prev[j - 1] ].min)
        end
        prev = curr
      end
      prev.last
    end
  end
end
