module Evaluation
  # Kind / minimum / level-definition inputs of the metric editor (wizard, new and edit forms).
  # Submits evaluation_metric[kind|minimum|levels_text]; MetricsController turns levels_text into Metric#levels.
  class MetricDefinitionFieldsComponent < ViewComponent::Base
    HINTS = {
      "probability" => "Yes/no question; no levels needed.",
      "score" => "Levels, one per line, worst first.",
      "choice" => "One option per line: option | value (0.0-1.0) | description."
    }.freeze

    def initialize(kind: "probability", minimum: nil, levels: nil)
      @kind = kind
      @minimum = minimum
      @levels = levels
    end

    def kind_options
      Metric::KINDS.map { |kind| [ kind.capitalize, kind ] }
    end

    def selected_kind = @kind
    def minimum = @minimum
    def hints = HINTS

    def levels_text
      MetricLevelsText.dump(kind: @kind, levels: @levels)
    end
  end
end
