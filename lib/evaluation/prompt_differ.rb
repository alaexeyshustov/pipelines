
module Evaluation
  class PromptDiffer
    Line = Data.define(:text, :type)

    def initialize(prompt_a, prompt_b)
      @prompt_a = prompt_a
      @prompt_b = prompt_b
    end

    def system_prompt_diff
      diff_lines(@prompt_a.system_prompt.to_s, @prompt_b.system_prompt.to_s)
    end

    def user_prompt_diff
      diff_lines(@prompt_a.user_prompt.to_s, @prompt_b.user_prompt.to_s)
    end

    private

    def diff_lines(text_a, text_b)
      Diffy::Diff.new(text_a, text_b).to_s.lines.filter_map do |line|
        next if line.match?(/\A(@@|\\|---|\+\+\+)/)

        Line.new(
          text: line[1..].to_s.chomp,
          type: case line[0]
                when "+" then :added
                when "-" then :removed
                else          :unchanged
                end
        )
      end
    end
  end
end
