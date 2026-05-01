# frozen_string_literal: true

module Evaluation
  class PromptDiffComponent < ViewComponent::Base
    def initialize(prompt_a:, prompt_b:)
      @prompt_a = prompt_a
      @prompt_b = prompt_b
      @differ = PromptDiffer.new(prompt_a, prompt_b)
    end

    def system_prompt_diff
      @differ.system_prompt_diff
    end

    def user_prompt_diff
      @differ.user_prompt_diff
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
  end
end
