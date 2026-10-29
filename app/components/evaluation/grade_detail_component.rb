module Evaluation
  # Drill-down of one graded metric: normalized score, verdict, and the raw judge answer
  # (level label, probabilities, confidence) stored in evaluation_evaluation_results.raw.
  class GradeDetailComponent < ViewComponent::Base
    def initialize(result:)
      @result = result
    end

    def score_label = @result.score && ScoreFormatter.percent(@result.score, digits: 1)

    def verdict
      case @result.passed
      when true then { label: "passed", variant: :success }
      when false then { label: "failed", variant: :danger }
      end
    end

    def confidence_label
      ScoreFormatter.percent(@result.confidence) unless @result.confidence.nil?
    end

    # The judged level: chosen option (choice), closest level description (score) or yes-probability (probability).
    def level_label
      case raw["type"].to_s
      when "choice" then raw["choice"].to_s.presence
      when "score" then score_level
      when "probability" then ("#{ScoreFormatter.percent(raw['probability'])} likely true" if raw["probability"])
      end
    end

    def probabilities
      value = raw["probabilities"]
      return [] unless value.is_a?(Hash)

      value.map { |name, probability| [ name.to_s, ScoreFormatter.percent(probability) ] }
    end

    def raw?
      raw.any?
    end

    private

    def raw
      value = @result.raw
      value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
    end

    def score_level
      levels = raw["levels"]
      return unless raw["score"] && levels.is_a?(Array) && levels.any?

      index = raw["score"].to_f.round.clamp(0, levels.size - 1)
      "level #{index}: #{levels[index]}"
    end
  end
end
