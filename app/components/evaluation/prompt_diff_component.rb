# frozen_string_literal: true

module Evaluation
  class PromptDiffComponent < ViewComponent::Base
    Line = Data.define(:text, :type)

    def initialize(prompt_a:, prompt_b:)
      @prompt_a = prompt_a
      @prompt_b = prompt_b
    end

    def system_prompt_diff
      diff_lines(@prompt_a.system_prompt.to_s, @prompt_b.system_prompt.to_s)
    end

    def user_prompt_diff
      diff_lines(@prompt_a.user_prompt.to_s, @prompt_b.user_prompt.to_s)
    end

    def line_class(line)
      case line.type
      when :added   then "bg-green-100 text-green-800"
      when :removed then "bg-red-100 text-red-800"
      else               "text-gray-700"
      end
    end

    def line_prefix(line)
      case line.type
      when :added   then "+"
      when :removed then "−"
      else               " "
      end
    end

    def version_a = "v#{@prompt_a.version}"
    def version_b = "v#{@prompt_b.version}"

    private

    def diff_lines(text_a, text_b)
      lines_a = text_a.lines.map(&:chomp)
      lines_b = text_b.lines.map(&:chomp)
      lcs = longest_common_subsequence(lines_a, lines_b)
      build_diff(lines_a, lines_b, lcs)
    end

    def longest_common_subsequence(a, b)
      m, n = a.size, b.size
      dp = Array.new(m + 1) { Array.new(n + 1, 0) }
      (1..m).each do |i|
        (1..n).each do |j|
          dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : [ dp[i - 1][j], dp[i][j - 1] ].max
        end
      end
      dp
    end

    def build_diff(a, b, dp)
      result = []
      i, j = a.size, b.size
      while i > 0 || j > 0
        if i > 0 && j > 0 && a[i - 1] == b[j - 1]
          result.unshift(Line.new(text: a[i - 1], type: :unchanged))
          i -= 1
          j -= 1
        elsif j > 0 && (i.zero? || dp[i][j - 1] >= dp[i - 1][j])
          result.unshift(Line.new(text: b[j - 1], type: :added))
          j -= 1
        else
          result.unshift(Line.new(text: a[i - 1], type: :removed))
          i -= 1
        end
      end
      result
    end
  end
end
