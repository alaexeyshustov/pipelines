module Evaluation
  # Display helpers for normalized scores (0.0..1.0). Scores are shown as percentages, deltas in percentage points.
  module ScoreFormatter
    PLACEHOLDER = "—".freeze

    module_function

    def percent(score, digits: 0)
      return PLACEHOLDER if score.nil?

      "#{(score.to_f * 100).round(digits)}%"
    end

    def points(delta)
      return PLACEHOLDER if delta.nil?

      points = (delta.to_f * 100).round(1)
      "#{'+' if points >= 0}#{points} pts"
    end

    def cost(amount)
      return PLACEHOLDER if amount.nil?

      "$#{format('%.4f', amount.to_f)}"
    end

    def tokens(count)
      count.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    end
  end
end
