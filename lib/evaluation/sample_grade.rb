module Evaluation
  # Overall grade of one sample: mean of its metric grades weighted by Metric#weight.
  # Unknown grades (nil score) and grades without a matching metric are excluded.
  # Returns nil when nothing is gradeable (not 0.0: "no data" must not read as "worst").
  class SampleGrade
    def self.call(grades:, metrics:)
      new(grades:, metrics:).call
    end

    def initialize(grades:, metrics:)
      @grades = grades
      @metrics = metrics.index_by(&:name)
    end

    def call
      weighted = weighted_scores
      total = weighted.sum { |_, weight| weight }
      return if total.zero?

      weighted.sum { |score, weight| score * weight } / total
    end

    private

    def weighted_scores
      pairs = [] # : Array[[Float, Float]]
      @grades.each do |grade|
        score = grade.score
        weight = @metrics[grade.metric_name]&.weight.to_f
        pairs << [ score, weight ] if score && weight.positive?
      end
      pairs
    end
  end
end
