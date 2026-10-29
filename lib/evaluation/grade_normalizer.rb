module Evaluation
  # Maps one native RubyLLM answer to a single float in 0.0..1.0 (higher is better), or nil when
  # the answer is unknown / unusable.
  #
  #   Probability -> probability                       Score  -> score / (levels - 1)
  #   Choice      -> sum(probability_i * value_i)      true/false -> 1.0 / 0.0, nil -> nil
  #
  # Choice option values come from +metric.levels+: { "option" => { "description" => ..., "value" => 0.0..1.0 } }.
  # An option without "value" counts 1.0 when it has "pass" => true, else 0.0 (a single pass option set).
  class GradeNormalizer
    def self.call(value:, metric:)
      new(value:, metric:).call
    end

    def initialize(value:, metric:)
      @value = value
      @metric = metric
    end

    def call
      clamp(native_number(@value))
    end

    private

    def native_number(value)
      case value
      when RubyLLM::Probability then value.probability
      when RubyLLM::Score then score_fraction(value)
      when RubyLLM::Choice then choice_expectation(value)
      when true then 1.0
      when false then 0.0
      end
    end

    def score_fraction(score)
      top = score.levels.size - 1
      return unless top.positive?

      score.score.to_f / top
    end

    def choice_expectation(choice)
      options = @metric.levels
      return unless options.is_a?(Hash) && choice.probabilities.any?

      total = 0.0
      choice.probabilities.each do |option, probability|
        definition = options[option.to_s]
        return nil unless definition

        total += probability.to_f * option_value(definition)
      end
      total
    end

    def option_value(definition)
      return 0.0 unless definition.is_a?(Hash)

      raw = definition["value"]
      return Float(raw.to_s) unless raw.nil?

      definition["pass"] ? 1.0 : 0.0
    end

    def clamp(number)
      return unless number.is_a?(Numeric) && number.to_f.finite?

      number.to_f.clamp(0.0, 1.0)
    end
  end
end
