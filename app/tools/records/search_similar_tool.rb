module Records
  class SearchSimilarTool < RubyLLM::Tool
    description "Search a database column for values similar to a given string. " \
                "Matches on substrings in both directions and word-level edit distance. " \
                "Useful for finding variant spellings of company names or job titles before normalizing."

    param :table,  type: :string, desc: "Table name: application_mails or interviews", required: true
    param :column, type: :string, desc: "Column to search (e.g. 'company', 'job_title')",  required: true
    param :value,  type: :string, desc: "Value to find similar matches for", required: true

    def name = "search_similar"

    def execute(table:, column:, value:)
      model = resolve_model(table)
      raise ArgumentError, "Unknown column '#{column}' for #{table}" unless model::COLUMN_NAMES.include?(column)

      substring_matches = fetch_substring_matches(model, column, value)
      fuzzy_matches     = fetch_fuzzy_matches(model, column, value)

      { matches: (substring_matches + fuzzy_matches).uniq.sort }
    end

    private

    # SQL: stored value contains query OR query contains stored value.
    def fetch_substring_matches(model, column, value)
      quoted = model.connection.quote_column_name(column)
      sql    = <<~SQL
        SELECT DISTINCT #{quoted}
        FROM #{model.table_name}
        WHERE #{quoted} IS NOT NULL AND #{quoted} != ''
          AND (#{quoted} LIKE :like OR :value LIKE '%' || #{quoted} || '%')
        ORDER BY #{quoted}
      SQL

      model.connection.select_values(
        model.sanitize_sql([ sql, { value: value, like: "%#{value}%" } ])
      )
    end

    # Ruby-side: word-level Levenshtein — catches typos like "Softwear" → "Software".
    # Fetches all distinct non-null values and keeps those where the majority of
    # query words closely match a word in the stored value.
    def fetch_fuzzy_matches(model, column, value)
      query_words = normalize_words(value)
      return [] if query_words.empty?

      model.distinct.where.not(column => [ nil, "" ]).pluck(column).select do |stored|
        stored_words = normalize_words(stored)
        matched = query_words.count { |qw| stored_words.any? { |sw| words_similar?(qw, sw) } }
        matched.to_f / query_words.size >= 0.5
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

    def resolve_model(table)
      case table.to_s
      when "application_mails" then ApplicationMail
      when "interviews"        then Interview
      else raise ArgumentError, "Unknown table '#{table}'. Use: application_mails, interviews."
      end
    end
  end
end
