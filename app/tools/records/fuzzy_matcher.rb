module Records
  class FuzzyMatcher
    MATCH_THRESHOLD = 0.5

    def initialize(value)
      @query_words = normalize_words(value)
    end

    def matches?(stored)
      return false if @query_words.empty?

      stored_words = normalize_words(stored)
      matched = @query_words.count { |qw| stored_words.any? { |sw| words_similar?(qw, sw) } }
      matched.to_f / @query_words.size >= MATCH_THRESHOLD
    end

    private

    def normalize_words(str)
      str.downcase.gsub(/[^a-z0-9\s]/, " ").split
    end

    def words_similar?(word_a, word_b)
      return true  if word_a == word_b
      return false if word_a[0] != word_b[0]

      levenshtein(word_a, word_b) <= 2
    end

    def levenshtein(str_a, str_b)
      return str_b.length if str_a.empty?
      return str_a.length if str_b.empty?

      b_len = str_b.length
      prev  = (0..b_len).to_a
      str_a.each_char.with_index(1) do |char_a, row|
        curr = [ row ]
        str_b.each_char.with_index(1) do |char_b, col|
          diag = prev[col - 1]
          curr << (char_a == char_b ? diag : 1 + [ prev[col], curr.last, diag ].min)
        end
        prev = curr
      end
      prev.last
    end
  end
end
