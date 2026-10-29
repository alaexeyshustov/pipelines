module Evaluation
  module Judge
    # Active Metric rows -> the dynamic +questions:+ hash of RubyLLM::Judge#judge, one question per metric,
    # keyed by metric name. Metric#kind picks the native type; Metric#levels supplies its criteria.
    class Questions
      TYPES = { "probability" => :probability, "score" => :score, "choice" => :choice }.freeze
      CRITERIA_KEYS = { probability: :criteria, score: :levels, choice: :options }.freeze

      def self.call(metrics)
        metrics.to_h { |metric| [ metric.name.to_s, question_for(metric) ] }
      end

      def self.question_for(metric)
        type = TYPES.fetch(metric.kind)
        question = { type: type, instructions: metric.description } # : RubyLLM::Judge::question
        criteria = criteria_for(metric, type)
        question[CRITERIA_KEYS.fetch(type)] = criteria unless criteria.nil?
        question
      end

      # choice options are sent as {option => description}; values stay on our side (GradeNormalizer).
      def self.criteria_for(metric, type)
        levels = metric.levels
        return levels if type != :choice
        return unless levels.is_a?(Hash)

        levels.transform_values { |definition| definition.is_a?(Hash) ? definition["description"] : definition }
      end
      private_class_method :question_for, :criteria_for
    end
  end
end
